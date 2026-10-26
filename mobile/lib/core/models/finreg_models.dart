/// Cellen-side types for the FinReg integration API.
///
/// FinReg is a standalone product: Cellen reads its manifest and opens the
/// delegated workspaces in the browser, so nothing here mirrors FinReg's
/// Flutter packages. Only the fields Cellen actually consumes are modelled;
/// unknown fields in the responses are ignored.
class FinregWorkspace {
  const FinregWorkspace({
    required this.capabilityId,
    required this.title,
    required this.description,
    required this.route,
    required this.operational,
    required this.blockedReasons,
  });

  final String capabilityId;
  final String title;
  final String description;
  final String route;
  final bool operational;
  final List<String> blockedReasons;

  factory FinregWorkspace.fromJson(Map<String, dynamic> value) =>
      FinregWorkspace(
        capabilityId: value['capability_id']?.toString() ?? '',
        title: value['title']?.toString() ?? '',
        description: value['description']?.toString() ?? '',
        route: value['route']?.toString() ?? '',
        operational: value['operational'] as bool? ?? false,
        blockedReasons:
            List<String>.from(value['blocked_reasons'] as List? ?? const []),
      );
}

/// The authoritative composition FinReg reports for this school.
class FinregManifest {
  const FinregManifest({
    required this.companyId,
    required this.apiVersion,
    required this.schemaVersion,
    required this.vertical,
    required this.agtChannel,
    required this.nonFiscal,
    required this.manifestFingerprint,
    required this.countryPack,
    required this.workspaces,
  });

  final String? companyId;
  final String apiVersion;
  final String schemaVersion;
  final String vertical;
  final String agtChannel;
  final bool nonFiscal;
  final String? manifestFingerprint;
  final String? countryPack;
  final List<FinregWorkspace> workspaces;

  /// Workspaces Cellen can offer here: operational, with an id to launch.
  List<FinregWorkspace> get operationalWorkspaces => workspaces
      .where((item) => item.operational && item.capabilityId.isNotEmpty)
      .toList(growable: false);

  factory FinregManifest.fromJson(Map<String, dynamic> value) => FinregManifest(
        companyId: value['company_id']?.toString(),
        apiVersion: value['api_version']?.toString() ?? '',
        schemaVersion: value['schema_version']?.toString() ?? '',
        vertical: value['vertical']?.toString() ?? '',
        agtChannel: value['agt_channel']?.toString() ?? 'disabled',
        nonFiscal: value['non_fiscal'] as bool? ?? false,
        manifestFingerprint: value['manifest_fingerprint']?.toString(),
        countryPack: value['country_pack']?.toString(),
        workspaces: (value['workspaces'] as List? ?? const [])
            .map((raw) =>
                FinregWorkspace.fromJson(Map<String, dynamic>.from(raw as Map)))
            .toList(growable: false),
      );
}

/// A single-use delegated launch: the URL to open, nothing else.
class FinregWorkspaceLaunch {
  const FinregWorkspaceLaunch({
    required this.url,
    required this.targetPath,
    required this.expiresIn,
  });

  final String url;
  final String? targetPath;
  final int? expiresIn;

  factory FinregWorkspaceLaunch.fromJson(Map<String, dynamic> value) =>
      FinregWorkspaceLaunch(
        url: value['url']?.toString() ?? '',
        targetPath: value['target_path']?.toString(),
        expiresIn: value['expires_in'] as int?,
      );
}
