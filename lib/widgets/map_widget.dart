import 'dart:html' as html;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class HtmlMapView extends StatefulWidget {
  final String elementId;
  final bool visible;

  const HtmlMapView({
    super.key,
    required this.elementId,
    this.visible = true,
  });

  @override
  State<HtmlMapView> createState() => _HtmlMapViewState();
}

class _HtmlMapViewState extends State<HtmlMapView> {
  @override
  void initState() {
    super.initState();

    // 요소가 존재하지 않는 경우 생성
    if (html.document.getElementById(widget.elementId) == null) {
      final mapDiv = html.DivElement()
        ..id = widget.elementId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.display = widget.visible ? 'block' : 'none';

      html.document.body!.append(mapDiv);
    }

    // HTML 요소를 Flutter에 등록
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      '${widget.elementId}-view',
      (int viewId) => html.document.getElementById(widget.elementId)!,
    );
  }

  @override
  void didUpdateWidget(HtmlMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 가시성 변경
    if (widget.visible != oldWidget.visible) {
      final element = html.document.getElementById(widget.elementId);
      if (element != null) {
        element.style.display = widget.visible ? 'block' : 'none';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: '${widget.elementId}-view',
    );
  }
}
