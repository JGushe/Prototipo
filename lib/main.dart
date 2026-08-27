import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tareas_screen.dart';
import 'screens/uso_screen.dart';
import 'screens/recomendaciones_screen.dart';
import 'services/notificacion_service.dart';
import 'services/uso_pantalla_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notif = NotificacionService();
  await notif.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prototipo Tesis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _indice = 0;

  final _pantallas = const [
    DashboardScreen(),
    TareasScreen(),
    UsoScreen(),
    RecomendacionesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Solicitar permisos al iniciar
    _solicitarPermisosIniciales();
  }

  Future<void> _solicitarPermisosIniciales() async {
    // Permiso de notificaciones (Android 13+)
    await Permission.notification.request();
    // Solicitar permiso de uso (abre ajustes)
    await UsoPantallaService().solicitarPermisoUso();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pantallas[_indice],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.task), label: 'Tareas'),
          NavigationDestination(icon: Icon(Icons.phone_android), label: 'Uso'),
          NavigationDestination(icon: Icon(Icons.lightbulb), label: 'Tips'),
        ],
      ),
    );
  }
}
