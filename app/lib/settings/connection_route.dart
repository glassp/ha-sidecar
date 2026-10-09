import 'connection_settings.dart';

/// What the network looks like right now (from the native monitor).
class NetworkState {
  const NetworkState({
    this.connected = true,
    this.wifi = false,
    this.ethernet = false,
    this.cellular = false,
    this.vpn = false,
    this.ssid,
    this.locationGranted = false,
  });

  final bool connected;
  final bool wifi;
  final bool ethernet;
  final bool cellular;
  final bool vpn;

  /// Null when unknown (not on Wi-Fi, or the location permission is missing).
  final String? ssid;
  final bool locationGranted;

  factory NetworkState.fromMap(Map<dynamic, dynamic>? m) => m == null
      ? const NetworkState()
      : NetworkState(
          connected: m['connected'] != false,
          wifi: m['wifi'] == true,
          ethernet: m['ethernet'] == true,
          cellular: m['cellular'] == true,
          vpn: m['vpn'] == true,
          ssid: m['ssid'] as String?,
          locationGranted: m['location_granted'] == true,
        );
}

enum RouteKind { internal, external, waitingForHome, offline }

class ConnectionRoute {
  const ConnectionRoute(this.kind, [this.url]);
  final RouteKind kind;

  /// The address to use; null when the policy says not to connect, or there is no network.
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is ConnectionRoute && other.kind == kind && other.url == url;
  @override
  int get hashCode => Object.hash(kind, url);
}

/// True if the tablet is on a network the user marked as home. With no home Wi-Fi configured the position is unknown
/// and the internal address is tried (the pre-existing behaviour), so nothing breaks for people who do not set this up.
bool isHomeNetwork(ConnectionSettings s, NetworkState n) {
  if (n.vpn && s.vpnIsHome) return true;
  if (n.ethernet && s.ethernetIsHome) return true;
  final ssid = n.ssid;
  if (ssid != null && s.homeSsids.contains(ssid)) return true;
  return false;
}

/// Which address to connect to (same idea as the companion app's internal/external URL), or none.
ConnectionRoute chooseRoute(ConnectionSettings s, NetworkState n) {
  if (!n.connected) return const ConnectionRoute(RouteKind.offline);
  final configured = s.homeSsids.isNotEmpty || s.vpnIsHome;
  final home = isHomeNetwork(s, n);
  if (s.policy == ConnectionPolicy.homeOnly && !home) {
    // cannot tell where we are without any home definition: do not lock the user out
    if (configured) return const ConnectionRoute(RouteKind.waitingForHome);
  }
  if (home || !configured || s.externalUrl.isEmpty) {
    return ConnectionRoute(RouteKind.internal, s.haUrl);
  }
  return ConnectionRoute(RouteKind.external, s.externalUrl);
}
