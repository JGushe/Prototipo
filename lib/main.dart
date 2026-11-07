import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tareas_screen.dart';
import 'screens/uso_screen.dart';
import 'screens/recomendaciones_screen.dart';
import 'screens/configuracion_screen.dart';
import 'database/database_helper.dart';
import 'models/perfil.dart';
import 'services/notificacion_service.dart';
import 'services/lectura_uso_controller.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notif = NotificacionService();
  await notif.init();
  await AparienciaController.instance.cargar();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Apariencia>(
      valueListenable: AparienciaController.instance,
      builder: (context, apariencia, _) => MaterialApp(
        title: 'Prototipo Tesis',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.of(apariencia.clara),
        darkTheme: AppTheme.of(apariencia.oscura),
        themeMode: apariencia.modo,
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.lectura});

  final LecturaUsoController? lectura;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _indice = 0;

  late final _lectura = widget.lectura ?? LecturaUsoController();
  late final _pantallas = [
    DashboardScreen(lectura: _lectura),
    const TareasScreen(),
    UsoScreen(lectura: _lectura),
    RecomendacionesScreen(lectura: _lectura),
    const ConfiguracionScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lectura.leer();
    // Onboarding mínimo: perfil opcional en el primer arranque.
    WidgetsBinding.instance.addPostFrameCallback((_) => _perfilInicial());
  }

  Future<void> _perfilInicial() async {
    try {
      final perfil = await DatabaseHelper.instance.obtenerPerfil();
      if (!mounted || perfil != null) return;
      await showDialog<Perfil>(
        context: context,
        builder: (_) => const PerfilDialog(),
      );
      await AparienciaController.instance.recargarSugerencia();
    } catch (e) {
      debugPrint('Perfil inicial no disponible: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _lectura.leer(forzar: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.lectura == null) _lectura.dispose();
    super.dispose();
  }

  void _cambiarPestana(int indice) {
    if (_indice == indice) return;
    if (indice == 0 || indice == 2 || indice == 3) _lectura.leer();
    setState(() => _indice = indice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pantallas[_indice],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: _cambiarPestana,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.task), label: 'Tareas'),
          NavigationDestination(icon: Icon(Icons.phone_android), label: 'Uso'),
          NavigationDestination(icon: Icon(Icons.lightbulb), label: 'Tips'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Config'),
        ],
      ),
    );
  }
}
