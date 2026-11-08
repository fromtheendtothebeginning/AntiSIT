import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';

import 'scan_page.dart';

/// [ScanCapability] 的实现：整页推入 [ScanPage]。
class ScanCapabilityImpl extends ScanCapability {
  const ScanCapabilityImpl();

  @override
  Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ScanPage()),
      );
}
