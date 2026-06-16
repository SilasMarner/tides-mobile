// Static reference data for well-known Texas fishing tournaments. This is
// guidance, not enforcement — requirements are summarized from the official
// rules so anglers know what to record, but the official site is the source
// of truth (linked via officialUrl) and rules change year to year.
class TournamentInfo {
  final String id;
  final String name;
  final String species;
  final String measuringMethod;
  final String deadline;
  final bool gpsRequired;
  final bool photoRequired;
  final String officialUrl;
  final List<String> requirements;

  const TournamentInfo({
    required this.id,
    required this.name,
    required this.species,
    required this.measuringMethod,
    required this.deadline,
    required this.gpsRequired,
    required this.photoRequired,
    required this.officialUrl,
    required this.requirements,
  });
}

const kTournaments = [
  TournamentInfo(
    id: 'tsr',
    name: 'Texas Shark Rodeo',
    species: 'Sharks (Texas state waters)',
    measuringMethod:
        'Total length: tip of snout to longest tail tip. Fork length: tip of '
        'snout to inside of tail. Girth: around thickest part between '
        'pectoral and dorsal fins.',
    deadline: 'Submit within 21 days of catch',
    gpsRequired: true,
    photoRequired: true,
    officialUrl: 'https://texassharkrodeo.com/Rules-Info',
    requirements: [
      'Catch must be from Texas state waters',
      'GPS coordinates required (decimal degrees or DMS)',
      'Total length, fork length, and girth measurements',
      'Photo per TSR photo rules',
      'Tag number if shark is ≥32" and tagged for release',
      'Fin clip sample optional, for bonus points',
    ],
  ),
  TournamentInfo(
    id: 'star',
    name: 'CCA Texas STAR',
    species: 'Redfish, trout, flounder, offshore + youth divisions',
    measuringMethod:
        'Photo of the fish on the official STAR measuring device, per '
        'published Means & Methods.',
    deadline:
        'Weigh in within 24h (inshore / tagged redfish / youth) or 36h '
        '(offshore) of catch',
    gpsRequired: false,
    photoRequired: true,
    officialUrl: 'https://startournament.org/',
    requirements: [
      'Current CCA membership + STAR entry + TX fishing license',
      'Photo of fish measured on the official device, texted with angler name',
      'Weigh in at an Official STAR Weigh Station within the deadline',
      'Signed official weigh-in registration form',
    ],
  ),
];

TournamentInfo? tournamentById(String? id) {
  if (id == null) return null;
  for (final t in kTournaments) {
    if (t.id == id) return t;
  }
  return null;
}
