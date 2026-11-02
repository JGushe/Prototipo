// Pruebas de la resolución de nombres de app (`_nombreApp`).
//
// El plugin no está registrado en el entorno de pruebas: se simula el canal
// 'usage_stats' con TestDefaultBinaryMessenger. `obtenerTopAppsDelDia` no toca
// la base de datos, así que el servicio se puede probar aislado.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_tesis/services/uso_pantalla_service.dart';

const MethodChannel _canalUso = MethodChannel('usage_stats');

Map<String, Object?> _stat(String paquete, int ms) => {
      'packageName': paquete,
      'totalTimeInForeground': '$ms',
    };

Map<String, Object?> _appInfo(String paquete, String? nombre) => {
      'packageName': paquete,
      'appName': nombre,
      'isSystemApp': 'false',
      'enabled': 'true',
      'versionCode': '1',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    mensajero.setMockMethodCallHandler(_canalUso, null);
  });

  test('consulta exitosa usa el nombre del plugin', () async {
    mensajero.setMockMethodCallHandler(_canalUso, (call) async {
      if (call.method == 'queryUsageStats') {
        return [_stat('com.whatsapp', 1200000)];
      }
      if (call.method == 'getAppInfo') {
        return _appInfo('com.whatsapp', 'WhatsApp');
      }
      return null;
    });

    final apps = await UsoPantallaService().obtenerTopAppsDelDia();

    expect(apps, hasLength(1));
    expect(apps.single.nombreApp, 'WhatsApp');
    expect(apps.single.nombrePaquete, 'com.whatsapp');
  });

  test('paquete no resuelto (null) cae al packageName', () async {
    mensajero.setMockMethodCallHandler(_canalUso, (call) async {
      if (call.method == 'queryUsageStats') {
        return [_stat('com.whatsapp', 1200000)];
      }
      return null; // getAppInfo devuelve null: paquete no resuelto.
    });

    final apps = await UsoPantallaService().obtenerTopAppsDelDia();

    expect(apps.single.nombreApp, 'com.whatsapp');
  });

  test('PlatformException cae al packageName y registra una sola vez', () async {
    final logs = <String>[];
    final debugPrintOriginal = debugPrint;
    debugPrint = (String? mensaje, {int? wrapWidth}) {
      if (mensaje != null) logs.add(mensaje);
    };
    addTearDown(() => debugPrint = debugPrintOriginal);

    mensajero.setMockMethodCallHandler(_canalUso, (call) async {
      if (call.method == 'queryUsageStats') {
        return [_stat('com.whatsapp', 1200000)];
      }
      throw PlatformException(code: 'usage_stats_error', message: 'fallo nativo');
    });

    final servicio = UsoPantallaService();
    final primera = await servicio.obtenerTopAppsDelDia();
    final segunda = await servicio.obtenerTopAppsDelDia();

    expect(primera.single.nombreApp, 'com.whatsapp');
    expect(segunda.single.nombreApp, 'com.whatsapp');
    // Dos capturas del mismo paquete: un único log.
    expect(logs, hasLength(1));
    expect(logs.single, contains('com.whatsapp'));
    expect(logs.single, contains('usage_stats_error'));
  });

  test('MissingPluginException cae al packageName', () async {
    mensajero.setMockMethodCallHandler(_canalUso, (call) async {
      if (call.method == 'queryUsageStats') {
        return [_stat('com.whatsapp', 1200000)];
      }
      throw MissingPluginException('sin plugin');
    });

    final apps = await UsoPantallaService().obtenerTopAppsDelDia();

    expect(apps.single.nombreApp, 'com.whatsapp');
  });
}
