import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF102A33);
  static const ink = Color(0xFF17313B);
  static const muted = Color(0xFF71858C);
  static const canvas = Color(0xFFF2F6F5);
  static const card = Color(0xFFFFFFFF);
  static const green = Color(0xFF08B866);
  static const greenDark = Color(0xFF087F51);
  static const blue = Color(0xFF2589D8);
  static const amber = Color(0xFFE19A2A);
  static const red = Color(0xFFD93B50);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.light,
      surface: AppColors.card,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      useMaterial3: true,
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'sans-serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.green.withValues(alpha: .13),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          color: states.contains(WidgetState.selected) ? AppColors.greenDark : AppColors.muted,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        )),
      ),
    );
  }
}
