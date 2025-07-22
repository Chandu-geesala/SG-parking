import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';



enum AppTheme { light, dark }

class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'app_theme';
  AppTheme _currentTheme = AppTheme.light;
  SharedPreferences? _prefs;

  AppTheme get currentTheme => _currentTheme;

  // Get the actual theme mode based on current selection
  ThemeMode get themeMode {
    switch (_currentTheme) {
      case AppTheme.light:
        return ThemeMode.light;
      case AppTheme.dark:
        return ThemeMode.dark;
    }
  }

  // Initialize theme from shared preferences
  Future<void> initializeTheme() async {
    _prefs = await SharedPreferences.getInstance();
    final themeIndex = _prefs?.getInt(_themeKey) ?? 0; // Default to light
    _currentTheme = AppTheme.values[themeIndex];
    notifyListeners();
  }

  // Toggle between themes: Light -> Dark -> Light...
  Future<void> toggleTheme() async {
    switch (_currentTheme) {
      case AppTheme.light:
        _currentTheme = AppTheme.dark;
        break;
      case AppTheme.dark:
        _currentTheme = AppTheme.light;
        break;
    }

    await _saveTheme();
    notifyListeners();
  }

  // Set specific theme
  Future<void> setTheme(AppTheme theme) async {
    _currentTheme = theme;
    await _saveTheme();
    notifyListeners();
  }

  // Save theme to shared preferences
  Future<void> _saveTheme() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_themeKey, _currentTheme.index);
  }

  // Get theme icon based on current theme
  IconData getThemeIcon() {
    switch (_currentTheme) {
      case AppTheme.light:
        return Icons.light_mode_rounded;
      case AppTheme.dark:
        return Icons.dark_mode_rounded;
    }
  }

  // Get theme name for display
  String getThemeName() {
    switch (_currentTheme) {
      case AppTheme.light:
        return 'Light';
      case AppTheme.dark:
        return 'Dark';
    }
  }
}



class AppThemes {
  // Light Theme (unchanged)
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Colors.grey[50],
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.grey.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );

  // Enhanced Dark Theme with attractive colors
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6), // Bright blue
      brightness: Brightness.dark,
    ).copyWith(
      // Custom attractive dark colors
      surface: const Color(0xFF1A1B23), // Deep dark blue-grey
      surfaceVariant: const Color(0xFF252730), // Slightly lighter surface
      onSurface: const Color(0xFFF8FAFC), // Clean white text
      onSurfaceVariant: const Color(0xFFCBD5E1), // Light grey text
      primary: const Color(0xFF60A5FA), // Vibrant blue
      primaryContainer: const Color(0xFF1E3A8A), // Dark blue container
      onPrimary: const Color(0xFFFFFFFF), // White on primary
      onPrimaryContainer: const Color(0xFF93C5FD), // Light blue on container
      secondary: const Color(0xFF34D399), // Attractive green
      secondaryContainer: const Color(0xFF064E3B), // Dark green container
      onSecondary: const Color(0xFF000000), // Black on secondary
      onSecondaryContainer: const Color(0xFF6EE7B7), // Light green on container
      tertiary: const Color(0xFFF472B6), // Attractive pink
      tertiaryContainer: const Color(0xFF831843), // Dark pink container
      error: const Color(0xFFEF4444), // Vibrant red
      errorContainer: const Color(0xFF7F1D1D), // Dark red container
      outline: const Color(0xFF475569), // Subtle outline
      outlineVariant: const Color(0xFF334155), // Darker outline
    ),
    scaffoldBackgroundColor: const Color(0xFF0F172A), // Very dark navy
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E293B), // Dark slate with slight blue tint
      foregroundColor: Color(0xFFF8FAFC), // Clean white
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardTheme(
      color: const Color(0xFF1E293B), // Dark slate card
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.3),
      surfaceTintColor: const Color(0xFF334155), // Subtle tint
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFF334155).withOpacity(0.3),
          width: 0.5,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    // Enhanced input decoration theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF334155),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: const Color(0xFF475569).withOpacity(0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF60A5FA),
          width: 2,
        ),
      ),
      labelStyle: const TextStyle(color: Color(0xFFCBD5E1)),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
    ),
    // Enhanced floating action button theme
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF60A5FA),
      foregroundColor: Colors.white,
      elevation: 6,
    ),
    // Enhanced chip theme
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF334155),
      labelStyle: const TextStyle(color: Color(0xFFF8FAFC)),
      selectedColor: const Color(0xFF60A5FA),
      secondarySelectedColor: const Color(0xFF34D399),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    // Enhanced dialog theme
    dialogTheme: DialogTheme(
      backgroundColor: const Color(0xFF1E293B),
      surfaceTintColor: const Color(0xFF334155),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    // Enhanced bottom sheet theme
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E293B),
      surfaceTintColor: Color(0xFF334155),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    // Enhanced divider theme
    dividerTheme: const DividerThemeData(
      color: Color(0xFF334155),
      thickness: 1,
    ),
    // Enhanced switch theme
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return const Color(0xFF60A5FA);
        }
        return const Color(0xFF64748B);
      }),
      trackColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return const Color(0xFF60A5FA).withOpacity(0.3);
        }
        return const Color(0xFF475569);
      }),
    ),
    // Enhanced text theme with better contrast
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: Color(0xFFF8FAFC)),
      displayMedium: TextStyle(color: Color(0xFFF8FAFC)),
      displaySmall: TextStyle(color: Color(0xFFF8FAFC)),
      headlineLarge: TextStyle(color: Color(0xFFF8FAFC)),
      headlineMedium: TextStyle(color: Color(0xFFF8FAFC)),
      headlineSmall: TextStyle(color: Color(0xFFF8FAFC)),
      titleLarge: TextStyle(color: Color(0xFFF8FAFC)),
      titleMedium: TextStyle(color: Color(0xFFF8FAFC)),
      titleSmall: TextStyle(color: Color(0xFFE2E8F0)),
      bodyLarge: TextStyle(color: Color(0xFFE2E8F0)),
      bodyMedium: TextStyle(color: Color(0xFFCBD5E1)),
      bodySmall: TextStyle(color: Color(0xFFCBD5E1)),
      labelLarge: TextStyle(color: Color(0xFFF8FAFC)),
      labelMedium: TextStyle(color: Color(0xFFE2E8F0)),
      labelSmall: TextStyle(color: Color(0xFFCBD5E1)),
    ),
  );
}


class ThemeSwitchWidget extends StatelessWidget {
  const ThemeSwitchWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Container(
          margin: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
                // Add subtle border for dark mode
                border: Theme.of(context).brightness == Brightness.dark
                    ? Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  width: 0.5,
                )
                    : null,
              ),
              child: Icon(
                themeProvider.getThemeIcon(),
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            tooltip: "Switch to ${_getNextThemeName(themeProvider.currentTheme)}",
            onPressed: () {
              themeProvider.toggleTheme();
              _showThemeChangeSnackbar(context, themeProvider.getThemeName());
            },
          ),
        );
      },
    );
  }

  String _getNextThemeName(AppTheme currentTheme) {
    switch (currentTheme) {
      case AppTheme.light:
        return 'Dark Mode';
      case AppTheme.dark:
        return 'Light Mode';
    }
  }

  void _showThemeChangeSnackbar(BuildContext context, String themeName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to $themeName'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}






class ResponsiveUtils {
  // Breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;

  // Check device type
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
          MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  // Get responsive padding
  static EdgeInsets getResponsivePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(16);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 40, vertical: 20);
    } else {
      // Desktop: center content with max width
      final screenWidth = MediaQuery.of(context).size.width;
      final horizontalPadding = (screenWidth - 1200) / 2;
      return EdgeInsets.symmetric(
        horizontal: horizontalPadding > 40 ? horizontalPadding : 40,
        vertical: 20,
      );
    }
  }

  // Get responsive container constraints
  static BoxConstraints getResponsiveConstraints(BuildContext context) {
    if (isMobile(context)) {
      return const BoxConstraints();
    } else if (isTablet(context)) {
      return const BoxConstraints(maxWidth: 800);
    } else {
      return const BoxConstraints(maxWidth: 1200);
    }
  }

  // Get responsive font size
  static double getResponsiveFontSize(BuildContext context, double baseFontSize) {
    if (isMobile(context)) {
      return baseFontSize;
    } else if (isTablet(context)) {
      return baseFontSize * 1.1;
    } else {
      return baseFontSize * 1.2;
    }
  }

  // Get responsive spacing
  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    if (isMobile(context)) {
      return baseSpacing;
    } else if (isTablet(context)) {
      return baseSpacing * 1.2;
    } else {
      return baseSpacing * 1.5;
    }
  }

  // Get responsive grid count
  static int getResponsiveGridCount(BuildContext context) {
    if (isMobile(context)) {
      return 1;
    } else if (isTablet(context)) {
      return 2;
    } else {
      return 3;
    }
  }
}