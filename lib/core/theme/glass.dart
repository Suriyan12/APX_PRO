import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';

// ─── GlassCard ────────────────────────────────────────────────────────────────
//
// Outer Container carries shadow + border (outside the clip so shadow is visible).
// Inner ClipRRect + Stack: blur as Positioned.fill, content as sibling.
// On Flutter Web HTML renderer BackdropFilter occludes its own child tree —
// the Stack-sibling pattern is required for content to render above the blur.

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;
  final Color? tint;
  final bool highlight;
  final Color? glowColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = 20,
    this.tint,
    this.highlight = true,
    this.glowColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final effectiveTint = tint ?? ext.glassTint;
    final effectiveGlow = glowColor;

    Widget inner = ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Blur + tinted glass body
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // Glass body tint
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(color: effectiveTint),
            ),
          ),
          // Specular top-edge shimmer
          if (highlight)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1.5,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Color(0x70FFFFFF),
                      Color(0x50FFFFFF),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.3, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          // Content
          Padding(padding: padding, child: child),
        ],
      ),
    );

    Widget card = Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: ext.glassBorder, width: 1),
        boxShadow: effectiveGlow != null
            ? [
                BoxShadow(
                  color: effectiveGlow.withValues(alpha: 0.22),
                  blurRadius: 28,
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: ext.isDark ? 0.25 : 0.08),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: ext.isDark ? 0.22 : 0.06),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: const Color(0x08FFFFFF),
                  blurRadius: 1,
                  spreadRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
      ),
      child: inner,
    );

    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }
    return card;
  }
}

// ─── Cyan-tinted glass card (primary actions) ──────────────────────────────

class GlassCardCyan extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const GlassCardCyan({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = context.ext.primary;
    return GlassCard(
      padding: padding,
      tint: primary.withValues(alpha: 0.08),
      glowColor: primary,
      onTap: onTap,
      child: child,
    );
  }
}

// ─── GlassButton ─────────────────────────────────────────────────────────────
//
// THE standard APX PRO primary-action button — the single reusable CTA component
// used across the whole app. Premium pill-shaped glass with a brand gradient,
// soft glow, specular highlight, and full interaction states:
//   • hover   — subtle brightening (desktop/web pointer)
//   • pressed — scale-down + ripple splash
//   • focused — keyboard focus ring (Tab / D-pad) + Enter/Space activation
//   • disabled— dimmed, no glow, non-interactive
//   • loading — spinner in place of the label
// Sizing is responsive (larger on tablets). Three styles: primary (brand cyan),
// ghost (neutral), danger (destructive). Public API is unchanged so existing
// call sites keep working — do NOT hand-roll glass buttons elsewhere.

enum GlassButtonStyle { primary, ghost, danger }

class GlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final GlassButtonStyle style;
  final bool loading;
  final double? width;
  final double height;
  final double fontSize;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.style = GlassButtonStyle.primary,
    this.loading = false,
    this.width,
    this.height = 52,
    this.fontSize = 15,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final disabled = widget.onTap == null && !widget.loading;
    final interactive = widget.onTap != null && !widget.loading;

    // Responsive sizing — a touch larger on tablets for comfortable tap targets.
    final bool isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final double height = widget.height + (isTablet ? 6 : 0);
    final double fontSize = widget.fontSize + (isTablet ? 1 : 0);
    final double iconSize = (isTablet ? 19 : 17);
    final double radius = height / 2;

    // Style-driven palette.
    final Color accent;
    final Color labelColor;
    final bool hasGlow;
    switch (widget.style) {
      case GlassButtonStyle.primary:
        accent = ext.primary;
        labelColor = ext.primary;
        hasGlow = true;
      case GlassButtonStyle.danger:
        accent = ext.accentPink;
        labelColor = ext.accentPink;
        hasGlow = true;
      case GlassButtonStyle.ghost:
        accent = ext.textSecondary;
        labelColor = ext.textSecondary;
        hasGlow = false;
    }

    // Hover lifts the fill/border a notch for a responsive feel.
    final double lift = (_hovered && interactive) ? 0.06 : 0.0;

    // Gradient body — a diagonal wash of the accent for the premium finish.
    final Gradient bodyGradient = widget.style == GlassButtonStyle.ghost
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ext.glassTint.withValues(alpha: (ext.isDark ? 0.10 : 0.62) + lift),
              ext.glassTint.withValues(alpha: (ext.isDark ? 0.04 : 0.48) + lift),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.26 + lift),
              accent.withValues(alpha: 0.10 + lift),
            ],
          );

    final Color borderColor = disabled
        ? ext.glassBorder.withValues(alpha: 0.5)
        : (widget.style == GlassButtonStyle.ghost
            ? ext.glassBorder
            : accent.withValues(alpha: _focused ? 0.85 : (0.55 + lift)));

    final content = widget.loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: labelColor),
          )
        : Row(
            mainAxisSize: widget.width == null ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: iconSize, color: disabled ? ext.textMuted : labelColor),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: disabled ? ext.textMuted : labelColor,
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          );

    Widget core = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: widget.width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: (!disabled && hasGlow)
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: _focused
                        ? 0.42
                        : (_hovered ? 0.36 : 0.26)),
                    blurRadius: _focused || _hovered ? 26 : 20,
                    spreadRadius: -4,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: ext.isDark ? 0.20 : 0.06),
                    blurRadius: 14,
                    spreadRadius: -2,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Frosted blur (sizes to the content child below).
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              // Gradient body (dimmed when disabled).
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: disabled ? null : bodyGradient,
                    color: disabled ? ext.glassTextFieldFill : null,
                  ),
                ),
              ),
              // Specular top-edge highlight.
              if (!disabled)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1.4,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Color(0x66FFFFFF),
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              // Ripple + content layer. This is the ONLY non-positioned child,
              // so it determines the Stack's intrinsic size — essential for
              // auto-width (width == null) pills, which get unbounded width
              // constraints. Row.min hugs content; Row.max fills a set width.
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: interactive ? widget.onTap : null,
                  onHighlightChanged: (v) => setState(() => _pressed = v),
                  onHover: (v) => setState(() => _hovered = v),
                  onFocusChange: (v) => setState(() => _focused = v),
                  focusColor: accent.withValues(alpha: 0.10),
                  hoverColor: Colors.transparent,
                  splashColor: accent.withValues(alpha: 0.18),
                  highlightColor: accent.withValues(alpha: 0.08),
                  canRequestFocus: interactive,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.width == null ? 24 : 12,
                    ),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: interactive,
      label: widget.label,
      child: core,
    );
  }
}

// ─── GlassTextField ──────────────────────────────────────────────────────────

class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final BorderRadius borderRadius;
  final List<TextInputFormatter>? inputFormatters;

  const GlassTextField({
    super.key,
    this.controller,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.focusNode,
    this.textInputAction,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLines: obscureText ? 1 : maxLines,
            maxLength: maxLength,
            textInputAction: textInputAction,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            style: TextStyle(color: ext.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: ext.textMuted, fontSize: 14),
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              counterStyle: TextStyle(color: ext.textMuted, fontSize: 11),
              filled: true,
              fillColor: ext.glassTextFieldFill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: BorderSide(color: ext.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: BorderSide(color: ext.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: borderRadius,
                borderSide: BorderSide(
                  color: ext.primary.withValues(alpha: 0.65),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Orb background ──────────────────────────────────────────────────────────

class GlassOrbBackground extends StatelessWidget {
  final Widget child;

  const GlassOrbBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ext  = context.ext;
    return Stack(
      children: [
        // Dominant orb — top right (primary brand colour)
        Positioned(
          top: -size.height * 0.10,
          right: -size.width * 0.20,
          child: _Orb(size: size.width * 0.95, color: ext.orb1),
        ),
        // Secondary orb — mid left
        Positioned(
          top: size.height * 0.28,
          left: -size.width * 0.28,
          child: _Orb(size: size.width * 0.85, color: ext.orb2),
        ),
        // Tertiary orb — bottom centre
        Positioned(
          bottom: -size.height * 0.08,
          left: size.width * 0.05,
          child: _Orb(size: size.width * 0.75, color: ext.orb3),
        ),
        // Subtle warm centre glow for depth
        Positioned(
          top: size.height * 0.45,
          left: size.width * 0.25,
          child: _Orb(size: size.width * 0.5, color: ext.orb4),
        ),
        child,
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;

  const _Orb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: color.a * 0.3), Colors.transparent],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

// ─── Floating glass bottom navigation bar ────────────────────────────────────

class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: ext.glassBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: ext.primary.withValues(alpha: 0.10),
              blurRadius: 32,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: ext.isDark ? 0.35 : 0.10),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: Stack(
            children: [
              // Blur layer
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              // Glass body
              Positioned.fill(
                child: Container(color: ext.glassNavTint),
              ),
              // Top specular shimmer
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0x50FFFFFF),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Nav items
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (i) {
                  final item     = items[i];
                  final selected = i == currentIndex;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: SizedBox(
                      height: 70,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: selected
                              ? BoxDecoration(
                                  color: ext.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: ext.primary.withValues(alpha: 0.40),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: ext.primary.withValues(alpha: 0.20),
                                      blurRadius: 12,
                                      spreadRadius: -2,
                                    ),
                                  ],
                                )
                              : null,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selected ? item.activeIcon : item.icon,
                                color: selected
                                    ? ext.primary
                                    : ext.textSecondary,
                                size: 22,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: selected
                                      ? ext.primary
                                      : ext.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const GlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// ─── Glass app bar ────────────────────────────────────────────────────────────

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? bottom;
  final double bottomHeight;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.bottomHeight = 0,
  });

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + bottomHeight);

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: ext.glassAppBarTint,
                border: Border(
                  bottom: BorderSide(color: ext.glassBorderBottom, width: 1),
                ),
              ),
            ),
          ),
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: leading,
            automaticallyImplyLeading: leading == null,
            title: Text(
              title,
              style: TextStyle(
                color: ext.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            actions: actions,
            bottom: bottom != null
                ? PreferredSize(
                    preferredSize: Size.fromHeight(bottomHeight),
                    child: bottom!,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Glass dialog ─────────────────────────────────────────────────────────────

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required Widget child,
}) {
  final ext = context.ext;
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: ext.glassDialogBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 40,
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Positioned.fill(
                child: Container(color: ext.glassDialogTint),
              ),
              // Top specular
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1.5,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0x60FFFFFF),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

// ─── Glass divider ────────────────────────────────────────────────────────────

class GlassDivider extends StatelessWidget {
  final double indent;

  const GlassDivider({super.key, this.indent = 0});

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              ext.glassBorder.withValues(alpha: ext.isDark ? 0.30 : 0.20),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
