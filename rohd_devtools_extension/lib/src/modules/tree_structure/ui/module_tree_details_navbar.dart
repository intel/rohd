import 'package:flutter/material.dart';

class ModuleTreeDetailsNavbar extends StatelessWidget {
  const ModuleTreeDetailsNavbar({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0x1B1B1FEE),
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white.withOpacity(.60),
      selectedFontSize: 10,
      unselectedFontSize: 10,
      onTap: (value) {
        // Respond to item press.
      },
      items: const [
        BottomNavigationBarItem(
          label: 'Details',
          icon: Icon(Icons.info),
        ),
        BottomNavigationBarItem(
          label: 'Waveform',
          icon: Icon(Icons.cable),
        ),
        BottomNavigationBarItem(
          label: 'Schematic',
          icon: Icon(Icons.developer_board),
        ),
      ],
    );
  }
}
