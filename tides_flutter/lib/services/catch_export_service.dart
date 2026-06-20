import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/tournaments.dart';
import '../models/catch_entry.dart';
import '../utils/unit_format.dart';

/// Builds and sends a single email handing one or more catches off to a
/// tournament captain.
///
/// The email carries two things, because the captain needs both:
///  1. A **PDF report** — each catch's details followed by its photo, in order,
///     so the captain can read it top-to-bottom (info → picture → next catch)
///     without scrolling past a wall of text to a pile of loose attachments.
///  2. The **original photo files**, attached as-is, so the captain can
///     re-upload the untouched images to the official tournament website.
class CatchExportService {
  static final _dateFmt = DateFormat('MMM d, yyyy  h:mm a');

  /// Native side fires a clean ACTION_SEND intent. We don't use
  /// flutter_email_sender: its attachment path set `mailto:` data on the SEND
  /// intent, which made Gmail drop the body + photo (blank email).
  static const _channel = MethodChannel('com.mattbettinger.tides/email');

  static Future<void> emailCatches(
    List<CatchEntry> entries, {
    required String defaultRecipient,
    required bool metric,
  }) async {
    final subject =
        'Catch Log — ${entries.length} catch${entries.length == 1 ? '' : 'es'}';
    final body = _buildBody(entries);

    // Stage the originals into the shareable cache dir first (it recreates the
    // dir), then drop the generated PDF report alongside them.
    final photos = await _stageAttachments(entries);
    final pdfPath = await _stagePdf(entries, metric);

    await _channel.invokeMethod<void>('sendEmail', {
      'subject': subject,
      'body': body,
      'recipients': defaultRecipient.isNotEmpty ? [defaultRecipient] : <String>[],
      // PDF report first so it's the obvious thing to open, originals after.
      'attachments': [pdfPath, ...photos],
    });
  }

  /// Catch photos live in the app documents dir (`app_flutter/catch_photos`),
  /// which our FileProvider (res/xml/file_paths.xml) does not expose. Copy each
  /// photo into the temporary (cache) dir first — that IS a configured provider
  /// root — so the native side can share it as a content:// URI.
  static Future<List<String>> _stageAttachments(List<CatchEntry> entries) async {
    final paths = <String>[];
    final shareDir = await _shareDir(fresh: true);

    for (var i = 0; i < entries.length; i++) {
      final src = entries[i].photoPath;
      if (src == null) continue;
      final srcFile = File(src);
      if (!await srcFile.exists()) continue;
      // Prefix with the index so two catches can never produce the same staged
      // filename — some email apps de-duplicate attachments by display name.
      final name = src.split('/').last;
      final dest = '${shareDir.path}/${i}_$name';
      await srcFile.copy(dest);
      paths.add(dest);
    }
    return paths;
  }

  /// Build the PDF report and write it into the shareable cache dir. Must be
  /// called AFTER [_stageAttachments], which recreates the dir.
  static Future<String> _stagePdf(
      List<CatchEntry> entries, bool metric) async {
    final bytes = await _buildPdf(entries, metric);
    final shareDir = await _shareDir();
    // A friendly, dated filename — this is what the captain sees in the inbox.
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final path = '${shareDir.path}/Catch_Log_$stamp.pdf';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  static Future<Directory> _shareDir({bool fresh = false}) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/catch_share');
    if (fresh && await dir.exists()) {
      await dir.delete(recursive: true);
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ── PDF report ──────────────────────────────────────────────────────────────

  static Future<Uint8List> _buildPdf(
      List<CatchEntry> entries, bool metric) async {
    // Embed a Unicode TTF as the base theme font. The pdf package's default
    // Helvetica is a Latin-1 Type1 font with no glyph for the em-dash (U+2014)
    // we use in the title, so it printed a missing-glyph box; an embedded TTF
    // also covers smart quotes / degree signs / etc. a captain might type.
    final base = pw.Font.ttf(await rootBundle.load('assets/Roboto-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/Roboto-Bold.ttf'));
    final doc = pw.Document(
      title: 'Catch Log',
      theme: pw.ThemeData.withFont(base: base, bold: bold),
    );

    // Pre-decode every photo (async) before building the synchronous widget
    // tree. Decode through dart:ui so EXIF orientation is baked in (the pdf
    // package doesn't honour EXIF) and wide photos are downscaled to keep the
    // file small — the captain still gets the untouched originals as separate
    // attachments. We hand the pdf package raw RGBA (not a re-encoded PNG):
    // Android's Impeller renderer doesn't support toByteData(png), which threw
    // and silently dropped every photo from the report.
    final images = <int, pw.RawImage>{};
    for (var i = 0; i < entries.length; i++) {
      final src = entries[i].photoPath;
      if (src == null) continue;
      final f = File(src);
      if (!await f.exists()) continue;
      try {
        images[i] = await _pdfImage(await f.readAsBytes());
      } catch (_) {
        // A single unreadable photo shouldn't sink the whole report.
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          final children = <pw.Widget>[
            pw.Header(
              level: 0,
              text: 'Catch Log — ${entries.length} '
                  'catch${entries.length == 1 ? '' : 'es'}',
            ),
          ];
          for (var i = 0; i < entries.length; i++) {
            children.add(_pdfCatch(entries[i], images[i], metric));
            if (i != entries.length - 1) {
              children.add(pw.Divider(height: 28, color: PdfColors.grey400));
            }
          }
          return children;
        },
      ),
    );
    return doc.save();
  }

  static pw.Widget _pdfCatch(
      CatchEntry e, pw.RawImage? img, bool metric) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          e.species,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        for (final line in _catchLines(e, metric))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1),
            child: pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
          ),
        if (img != null) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            height: 280,
            alignment: pw.Alignment.centerLeft,
            child: pw.Image(img, fit: pw.BoxFit.contain),
          ),
        ],
      ],
    );
  }

  /// Decode → (optionally downscale) → hand the pdf package raw RGBA via dart:ui
  /// so the embedded image is upright (EXIF applied) and not full-camera
  /// resolution. We use rawRgba rather than re-encoding to PNG because
  /// `toByteData(format: png)` is unsupported under Android's Impeller renderer
  /// (it threw, which dropped the photo from the report); rawRgba always works.
  static Future<pw.RawImage> _pdfImage(Uint8List original) async {
    final probe = await ui.instantiateImageCodec(original);
    final probeFrame = await probe.getNextFrame();
    final w = probeFrame.image.width;
    probeFrame.image.dispose();

    final codec = w > 1400
        ? await ui.instantiateImageCodec(original, targetWidth: 1280)
        : await ui.instantiateImageCodec(original);
    final frame = await codec.getNextFrame();
    final rgba =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final iw = frame.image.width;
    final ih = frame.image.height;
    frame.image.dispose();
    return pw.RawImage(
        bytes: rgba!.buffer.asUint8List(), width: iw, height: ih);
  }

  // ── Shared text ───────────────────────────────────────────────────────────

  /// The short email body. The details now live in the attached PDF, so the
  /// body just orients the captain rather than repeating every catch.
  static String _buildBody(List<CatchEntry> entries) {
    final n = entries.length;
    return '$n catch${n == 1 ? '' : 'es'} attached.\n\n'
        'The attached PDF report lists each catch with its photo, in order. '
        'The original photo files are also attached so you can re-upload them.\n\n'
        '— Sent from OpenTides';
  }

  /// The per-catch detail lines, shared by the PDF (one block per catch).
  static List<String> _catchLines(CatchEntry e, bool metric) {
    final tournament = tournamentById(e.tournamentId);
    final lines = <String>['Caught: ${_dateFmt.format(e.caughtAt)}'];
    if (e.released && e.releasedAt != null) {
      lines.add('Released: ${_dateFmt.format(e.releasedAt!)}');
    }

    final measurements = <String>[
      if (e.lengthIn != null) 'Length ${fmtLenIn(e.lengthIn, metric)}',
      if (e.forkLengthIn != null) 'Fork length ${fmtLenIn(e.forkLengthIn, metric)}',
      if (e.girthIn != null) 'Girth ${fmtLenIn(e.girthIn, metric)}',
      if (e.weightLb != null) 'Weight ${fmtWeight(e.weightLb, metric)}',
    ];
    if (measurements.isNotEmpty) lines.add(measurements.join(' · '));

    lines.add(e.released ? 'Released' : 'Kept');

    if (e.sex != null) lines.add('Sex: ${e.sex}');
    if (e.tagNumber != null) lines.add('Tag number: ${e.tagNumber}');
    if (e.dnaSampleNumber != null) {
      lines.add('DNA sample number: ${e.dnaSampleNumber}');
    }
    if (e.isRecapture) {
      lines.add('Recapture: yes'
          '${e.recaptureTagNumber != null ? ' (original tag ${e.recaptureTagNumber})' : ''}');
    }

    if (e.lat != null && e.lon != null) {
      lines.add('GPS: ${e.lat!.toStringAsFixed(5)}, ${e.lon!.toStringAsFixed(5)}'
          '${e.locationLabel != null ? ' (${e.locationLabel})' : ''}');
    } else if (e.locationLabel != null) {
      lines.add('Location: ${e.locationLabel}');
    }

    if (tournament != null) lines.add('Tournament: ${tournament.name}');
    if (e.notes != null && e.notes!.isNotEmpty) lines.add('Notes: ${e.notes}');
    return lines;
  }
}
