import 'package:flutter/material.dart';

const premiumInk = Color(0xFF242221);
const premiumIvory = Color(0xFFF8F5EF);
const premiumGold = Color(0xFFAC884D);
const premiumFont = 'packages/ruralconnect_mobile/Manrope';

ThemeData ruralTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF1C1A18) : premiumIvory;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: premiumGold,
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFE9D5AE) : premiumInk,
        onPrimary: dark ? premiumInk : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF4D4131)
            : const Color(0xFFF0E6D5),
        onPrimaryContainer: dark ? premiumIvory : premiumInk,
        secondary: dark ? const Color(0xFFD4B681) : const Color(0xFF7A5A2D),
        secondaryContainer: dark
            ? const Color(0xFF3E3528)
            : const Color(0xFFF0E6D5),
        onSecondaryContainer: dark ? premiumIvory : const Color(0xFF534124),
        surface: dark ? const Color(0xFF262320) : const Color(0xFFFFFEFB),
        onSurface: dark ? const Color(0xFFF1ECE3) : premiumInk,
        onSurfaceVariant: dark
            ? const Color(0xFFC5BEB2)
            : const Color(0xFF706B62),
        outline: dark ? const Color(0xFF736A5D) : const Color(0xFFB6AC9C),
        outlineVariant: dark
            ? const Color(0xFF423B32)
            : const Color(0xFFE8E1D6),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: premiumFont,
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.3,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.55),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      scrolledUnderElevation: 0,
      toolbarHeight: 68,
      titleTextStyle: TextStyle(
        fontFamily: premiumFont,
        color: scheme.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.secondary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: premiumFont,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: .7,
      space: 28,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.primaryContainer,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(
        fontFamily: premiumFont,
        fontSize: 12,
        color: scheme.onPrimaryContainer,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      height: 76,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: premiumFont,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: scheme.onSurface, size: 23),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}

class PremiumHeading extends StatelessWidget {
  final String eyebrow, title, subtitle;
  const PremiumHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 24, height: 2, color: premiumGold),
            const SizedBox(width: 10),
            Text(
              eyebrow.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2.2,
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
