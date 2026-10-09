import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/settings/connection_route.dart';
import 'package:ha_sidecar/settings/connection_settings.dart';

void main() {
  const internal = 'http://ha.local:8123';
  const external = 'https://ha.example.org';
  const home = ['Home', 'Home 5G'];

  ConnectionSettings s({
    List<String> ssids = home,
    bool vpn = false,
    bool eth = true,
    String ext = external,
    ConnectionPolicy policy = ConnectionPolicy.always,
  }) => ConnectionSettings(
    haUrl: internal,
    token: 't',
    externalUrl: ext,
    homeSsids: ssids,
    vpnIsHome: vpn,
    ethernetIsHome: eth,
    policy: policy,
  );

  test('home Wi-Fi uses the internal address, other Wi-Fi the external one', () {
    expect(chooseRoute(s(), const NetworkState(wifi: true, ssid: 'Home')), const ConnectionRoute(RouteKind.internal, internal));
    expect(chooseRoute(s(), const NetworkState(wifi: true, ssid: 'Cafe')), const ConnectionRoute(RouteKind.external, external));
    expect(chooseRoute(s(), const NetworkState(cellular: true)), const ConnectionRoute(RouteKind.external, external));
  });

  test('a VPN counts as home only when the user says so', () {
    const vpnOnCellular = NetworkState(cellular: true, vpn: true);
    expect(chooseRoute(s(vpn: true), vpnOnCellular), const ConnectionRoute(RouteKind.internal, internal));
    expect(chooseRoute(s(vpn: false), vpnOnCellular), const ConnectionRoute(RouteKind.external, external));
  });

  test('ethernet counts as home by default', () {
    expect(chooseRoute(s(), const NetworkState(ethernet: true)), const ConnectionRoute(RouteKind.internal, internal));
    expect(chooseRoute(s(eth: false), const NetworkState(ethernet: true)), const ConnectionRoute(RouteKind.external, external));
  });

  test('without an external address the internal one is used everywhere', () {
    expect(chooseRoute(s(ext: ''), const NetworkState(wifi: true, ssid: 'Cafe')), const ConnectionRoute(RouteKind.internal, internal));
  });

  test('home-only policy waits away from home and connects at home', () {
    final p = s(policy: ConnectionPolicy.homeOnly);
    expect(chooseRoute(p, const NetworkState(wifi: true, ssid: 'Cafe')).kind, RouteKind.waitingForHome);
    expect(chooseRoute(p, const NetworkState(cellular: true)).kind, RouteKind.waitingForHome);
    expect(chooseRoute(p, const NetworkState(wifi: true, ssid: 'Home')).kind, RouteKind.internal);
  });

  test('nothing configured: behave as before and use the internal address', () {
    final p = s(ssids: const [], policy: ConnectionPolicy.homeOnly);
    expect(chooseRoute(p, const NetworkState(wifi: true, ssid: 'Cafe')), const ConnectionRoute(RouteKind.internal, internal));
  });

  test('no network at all', () {
    expect(chooseRoute(s(), const NetworkState(connected: false)).kind, RouteKind.offline);
  });
}
