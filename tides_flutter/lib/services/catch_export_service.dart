import 'dart:io';

import 'package:flutter/services.dart';
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
    final body = _buildBody(entries, metric);
    final attachments = await _stageAttachments(entries);

    await _channel.invokeMethod<void>('sendEmail', {
      'subject': subject,
      'body': body,
      'recipients': defaultRecipient.isNotEmpty ? [defaultRecipient] : <String>[],
      'attachments': attachments,
    });
  }

  /// Catch photos live in the app documents dir (`app_flutter/catch_photos`),
  /// which our FileProvider (res/xml/file_paths.xml) does not expose. Copy each
  /// photo into the temporary (cache) dir first — that IS a configured provider
  /// root — so the native side can share it as a content:// URI.
  static Future<List<String>> _stageAttachments(List<CatchEntry> entries) async {
    final paths = <String>[];
    final tmp = await getTemporaryDirectory();
    final shareDir = Directory('${tmp.path}/catch_share');
    if (await shareDir.exists()) {
      await shareDir.delete(recursive: true);
    }
    await shareDir.create(recursive: true);

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
