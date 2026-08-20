import 'package:flutter/material.dart';

/// Bottom navigation styled as cartridges in slots (the "launch box" shell):
/// the active tab is seated + lit amber, the others sit popped up in gray.
class CartridgeNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const CartridgeNavBar({super.key, required this.index, required this.onSelect});

  static const _items = <(IconData, String)>[
    (Icons.videogame_asset, 'GAMES'),
    (Icons.menu_book, 'DEX'),
    (Icons.settings, 'SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 94 + safe,
      padding: EdgeInsets.only(bottom: safe),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1D14), Color(0xFF140B06)],
        ),
        border: Border(top: BorderSide(color: Color(0xFF4A3220), width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _items.length; i++)
            _CartTab(
              icon: _items[i].$1,
              label: _items[i].$2,
              active: i == index,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _CartTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CartTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = active ? const Color(0xFF37220A) : const Color(0xFFC6BBA7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 104,
        height: 86,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // slot rail the cartridge drops into
            Positioned(
              left: 10,
              right: 10,
              top: 6,
              child: Container(
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF0C0906),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(5)),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0xB3000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                        spreadRadius: -1),
                  ],
                ),
              ),
            ),
            // the cartridge
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              bottom: 6,
              top: active ? 12 : 20,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: active
                        ? const [Color(0xFFEFBF5C), Color(0xFFC8892F)]
                        : const [Color(0xFF4A4F57), Color(0xFF2F343B)],
                  ),
                  border: Border.all(
                      color: active
                          ? const Color(0xFF7D5210)
                          : const Color(0xFF1C1F24)),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(9), bottom: Radius.circular(5)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x8C000000),
                        blurRadius: 10,
                        offset: Offset(0, 5)),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22, color: ink),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // notch centered on the cartridge top
            Positioned(
              top: active ? 10 : 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 34,
                  height: 7,
                  decoration: BoxDecoration(
                    color:
                        active ? const Color(0xFF7D5210) : const Color(0xFF15171B),
                    borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(5)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
