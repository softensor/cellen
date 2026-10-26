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
    this.navigableCapabilities = const [],
    this.erpCapabilities = const [],
    this.erpEntitled = false,
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

  /// What FinReg lets this tenant navigate. Additive; an older FinReg omits
  /// it and then the host falls back to the local plan mirror.
  final List<String> navigableCapabilities;

  /// The ERP workspaces FinReg has both entitled and composed.
  final List<String> erpCapabilities;

  /// Whether the ERP add-on is on this tenant's plan.
  final bool erpEntitled;

  /// Workspaces Cellen can offer here: operational, with an id to launch.
  List<FinregWorkspace> get operationalWorkspaces => workspaces
      .where((item) => item.operational && item.capabilityId.isNotEmpty)
      .toList(growable: false);

  factory FinregManifest.fromJson(Map<String, dynamic> value) {
    // New FinReg releases report `erp_entitled`/`erp_capabilities` directly.
    // Against an older one, the backend's `finreg_plan` already resolved the
    // school's local mirror, so the host keeps a truthful plan line.
    final legacyPlan = value['finreg_plan'] is Map
        ? Map<String, dynamic>.from(value['finreg_plan'] as Map)
        : const <String, dynamic>{};
    return FinregManifest(
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
      navigableCapabilities: List<String>.from(
          value['navigable_capabilities'] as List? ?? const []),
      erpCapabilities: List<String>.from(value['erp_capabilities'] as List? ??
          legacyPlan['erp_capabilities'] as List? ??
          const []),
      erpEntitled: value['erp_entitled'] as bool? ??
          legacyPlan['erp_enabled'] as bool? ??
          false,
    );
  }
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
