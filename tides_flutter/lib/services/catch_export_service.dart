import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:intl/intl.dart';
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
    final attachments = [
      for (final e in entries)
        if (e.photoPath != null) e.photoPath!,
    ];

    await FlutterEmailSender.send(Email(
      subject: subject,
      body: body,
      recipients: defaultRecipient.isNotEmpty ? [defaultRecipient] : [],
      attachmentPaths: attachments,
      isHTML: false,
    ));
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
