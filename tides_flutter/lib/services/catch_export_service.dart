import 'dart:io';

import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../data/tournaments.dart';
import '../models/catch_entry.dart';
import '../utils/unit_format.dart';

/// Builds and sends a single email containing the details + photos of one
/// or more catches — e.g. a team member handing catches off to a tournament
/// captain for entry on the official website.
class CatchExportService {
  static final _dateFmt = DateFormat('MMM d, yyyy  h:mm a');

  static Future<void> emailCatches(
    List<CatchEntry> entries, {
    required String defaultRecipient,
    required bool metric,
  }) async {
    final subject =
        'Catch Log — ${entries.length} catch${entries.length == 1 ? '' : 'es'}';
    final body = _buildBody(entries, metric);
    final attachments = await _stageAttachments(entries);

    await FlutterEmailSender.send(Email(
      subject: subject,
      body: body,
      recipients: defaultRecipient.isNotEmpty ? [defaultRecipient] : [],
      attachmentPaths: attachments,
      isHTML: false,
    ));
  }

  /// Catch photos live in the app documents dir (`app_flutter/catch_photos`),
  /// which is NOT one of the roots flutter_email_sender's bundled FileProvider
  /// exposes (it only maps files/, cache/ and external storage). Attaching a
  /// path outside those roots makes FileProvider.getUriForFile throw, which
  /// surfaced to users as "could not open an email app". Copy each photo into
  /// the temporary (cache) dir first — that IS a configured FileProvider root —
  /// and attach the copies.
  static Future<List<String>> _stageAttachments(List<CatchEntry> entries) async {
    final paths = <String>[];
    final tmp = await getTemporaryDirectory();
    final shareDir = Directory('${tmp.path}/catch_share');
    if (await shareDir.exists()) {
      await shareDir.delete(recursive: true);
    }
    await shareDir.create(recursive: true);

    for (final e in entries) {
      final src = e.photoPath;
      if (src == null) continue;
      final srcFile = File(src);
      if (!await srcFile.exists()) continue;
      final name = src.split('/').last;
      final dest = '${shareDir.path}/$name';
      await srcFile.copy(dest);
      paths.add(dest);
    }
    return paths;
  }

  static String _buildBody(List<CatchEntry> entries, bool metric) {
    final buf = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final tournament = tournamentById(e.tournamentId);

      buf.writeln(e.species);
      buf.writeln('Caught: ${_dateFmt.format(e.caughtAt)}');
      if (e.released && e.releasedAt != null) {
        buf.writeln('Released: ${_dateFmt.format(e.releasedAt!)}');
      }

      final measurements = <String>[
        if (e.lengthIn != null) 'Length ${fmtLenIn(e.lengthIn, metric)}',
        if (e.forkLengthIn != null)
          'Fork length ${fmtLenIn(e.forkLengthIn, metric)}',
        if (e.girthIn != null) 'Girth ${fmtLenIn(e.girthIn, metric)}',
        if (e.weightLb != null) 'Weight ${fmtWeight(e.weightLb, metric)}',
      ];
      if (measurements.isNotEmpty) buf.writeln(measurements.join(' · '));

      buf.writeln(e.released ? 'Released' : 'Kept');

      if (e.sex != null) buf.writeln('Sex: ${e.sex}');
      if (e.tagNumber != null) buf.writeln('Tag number: ${e.tagNumber}');
      if (e.dnaSampleNumber != null) {
        buf.writeln('DNA sample number: ${e.dnaSampleNumber}');
      }
      if (e.isRecapture) {
        buf.writeln('Recapture: yes'
            '${e.recaptureTagNumber != null ? ' (original tag ${e.recaptureTagNumber})' : ''}');
      }

      if (e.lat != null && e.lon != null) {
        buf.writeln(
            'GPS: ${e.lat!.toStringAsFixed(5)}, ${e.lon!.toStringAsFixed(5)}'
            '${e.locationLabel != null ? ' (${e.locationLabel})' : ''}');
      } else if (e.locationLabel != null) {
        buf.writeln('Location: ${e.locationLabel}');
      }

      if (tournament != null) buf.writeln('Tournament: ${tournament.name}');
      if (e.notes != null && e.notes!.isNotEmpty) {
        buf.writeln('Notes: ${e.notes}');
      }

      if (i != entries.length - 1) buf.writeln('\n---\n');
    }
    return buf.toString();
  }
}
