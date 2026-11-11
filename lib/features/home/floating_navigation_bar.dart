import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class FloatingNavigationBar extends StatefulWidget {
  const FloatingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  State<FloatingNavigationBar> createState() => _FloatingNavigationBarState();
}

class _FloatingNavigationBarState extends State<FloatingNavigationBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _position;
  late int _fromIcon, _toIcon;
  bool _reducedMotion = false;
  int get selectedIndex => widget.selectedIndex;
  List<NavigationDestination> get destinations => widget.destinations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 1,
    );
    _fromIcon = _toIcon = selectedIndex;
    _position = AlwaysStoppedAnimation(selectedIndex.toDouble());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion && _controller.isAnimating) _controller.value = 1;
  }

  @override
  void didUpdateWidget(FloatingNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destinations.length != destinations.length) {
      _controller.stop();
      _fromIcon = _toIcon = selectedIndex;
      _position = AlwaysStoppedAnimation(selectedIndex.toDouble());
      _controller.value = 1;
    } else if (oldWidget.selectedIndex != selectedIndex) {
      final current = _position.value;
      _fromIcon = _controller.value < .5 ? _fromIcon : _toIcon;
      _toIcon = selectedIndex;
      _position = _controller.drive(
        Tween(
          begin: current,
          end: selectedIndex.toDouble(),
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      );
      if (_reducedMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  Widget _activeIcon() {
    Widget icon(int index) =>
        destinations[index].selectedIcon ?? destinations[index].icon;
    if (_fromIcon == _toIcon) return icon(_toIcon);
    final progress = const Interval(
      .2,
      .8,
      curve: Curves.easeInOut,
    ).transform(_controller.value);
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 1 - progress,
          child: Transform.scale(
            scale: 1 - .15 * progress,
            child: KeyedSubtree(
              key: ValueKey('nav-outgoing-$_fromIcon'),
              child: icon(_fromIcon),
            ),
          ),
        ),
        Opacity(
          opacity: progress,
          child: Transform.scale(
            scale: .85 + .15 * progress,
            child: KeyedSubtree(
              key: ValueKey('nav-incoming-$_toIcon'),
              child: icon(_toIcon),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final slot = width / destinations.length;
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final position = _position.value;
                  final center = Directionality.of(context) == TextDirection.rtl
                      ? width - slot * (position + .5)
                      : slot * (position + .5);
                  return SizedBox(
                    height: 88,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _NavigationPainter(center, 31),
                          ),
                        ),
                        Positioned(
                          left: center - 25,
                          top: 0,
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Container(
                                key: const ValueKey('nav-active-indicator'),
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFF3D99B),
                                      AppTheme.accent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.accent.withValues(
                                        alpha: .24,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: IconTheme(
                                  data: const IconThemeData(
                                    color: AppTheme.brand,
                                    size: 25,
                                  ),
                                  child: _activeIcon(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Material(
                            type: MaterialType.transparency,
                            child: Row(
                              children: List.generate(destinations.length, (
                                index,
                              ) {
                                final destination = destinations[index];
                                final selected = index == selectedIndex;
                                return Expanded(
                                  child: Semantics(
                                    selected: selected,
                                    button: true,
                                    label: destination.label,
                                    child: Tooltip(
                                      message: destination.label,
                                      child: InkWell(
                                        key: ValueKey(
                                          'nav-${destination.label}',
                                        ),
                                        borderRadius: BorderRadius.circular(22),
                                        onTap: () {
                                          if (index != selectedIndex) {
                                            widget.onSelected(index);
                                          }
                                        },
                                        splashFactory: NoSplash.splashFactory,
                                        overlayColor:
                                            const WidgetStatePropertyAll(
                                              Colors.transparent,
                                            ),
                                        child: ExcludeSemantics(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              SizedBox(
                                                height: 32,
                                                child: Opacity(
                                                  opacity: index == _toIcon
                                                      ? 1 - _controller.value
                                                      : index == _fromIcon
                                                      ? _controller.value
                                                      : 1,
                                                  child: IconTheme(
                                                    data: const IconThemeData(
                                                      color: Color(0xFFBECCC5),
                                                      size: 23,
                                                    ),
                                                    child: destination.icon,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 3,
                                                    ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: AnimatedDefaultTextStyle(
                                                    duration: duration,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall!
                                                        .copyWith(
                                                          color: selected
                                                              ? const Color(
                                                                  0xFFF3D99B,
                                                                )
                                                              : const Color(
                                                                  0xFFBECCC5,
                                                                ),
                                                          fontWeight: selected
                                                              ? FontWeight.w800
                                                              : FontWeight.w500,
                                                        ),
                                                    child: Text(
                                                      destination.label,
                                                      maxLines: 1,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 13),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavigationPainter extends CustomPainter {
  const _NavigationPainter(this.center, this.radius);
  final double center, radius;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 16.0;
    final base = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top, size.width, size.height),
          const Radius.circular(20),
        ),
      );
    // The tangent shoulders keep the cradle flowing into the top edge.
    // A 31px cradle leaves 6px around the 25px floating indicator.
    final cradle = const CircularNotchedRectangle().getOuterPath(
      Rect.fromLTRB(0, top, size.width, size.height),
      Rect.fromCircle(center: Offset(center, 25), radius: radius),
    );
    final path = Path.combine(PathOperation.intersect, base, cradle);
    canvas.drawShadow(path, AppTheme.brand.withValues(alpha: .16), 7, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E5145), AppTheme.brand],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_NavigationPainter oldDelegate) =>
      center != oldDelegate.center || radius != oldDelegate.radius;
}
