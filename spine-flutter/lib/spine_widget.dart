import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/rendering.dart' as rendering;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'spine_flutter.dart';

class SpineWidgetController {
  Atlas? _atlas;
  SkeletonData? _data;
  SkeletonDrawable? _drawable;
  final void Function(SpineWidgetController controller)? onInitialized;
  bool initialized = false;

  SpineWidgetController([this.onInitialized]);

  void _initialize(Atlas atlas, SkeletonData data, SkeletonDrawable drawable) {
    if (initialized)
      throw Exception("SpineWidgetController already initialized. A controller can only be used with one widget.");
    _atlas = atlas;
    _data = data;
    _drawable = drawable;
    onInitialized?.call(this);
    initialized = true;
  }

  Atlas? get atlas => _atlas;

  SkeletonData? get skeletonData => _data;

  AnimationStateData? get animationStateData => _drawable?.animationStateData;

  AnimationState? get animationState => _drawable?.animationState;

  Skeleton? get skeleton => _drawable?.skeleton;
}

enum AssetType { Asset, File, Http, Raw }

abstract class BoundsProvider {
  const BoundsProvider();

  Bounds computeBounds(SkeletonDrawable drawable);
}

class SetupPoseBounds extends BoundsProvider {
  const SetupPoseBounds();

  Bounds computeBounds(SkeletonDrawable drawable) {
    return drawable.skeleton.getBounds();
  }
}

class RawBounds extends BoundsProvider {
  final double x, y, width, height;

  RawBounds(this.x, this.y, this.width, this.height);

  Bounds computeBounds(SkeletonDrawable drawable) {
    return Bounds(x, y, width, height);
  }
}

class ComputedBounds extends BoundsProvider {
  Bounds computeBounds(SkeletonDrawable drawable) {
    return Bounds(0, 0, 0, 0);
  }
}

class SpineWidget extends StatefulWidget {
  final AssetType _assetType;
  final String? skeletonFile;
  final String? atlasFile;
  final SkeletonData? skeletonData;
  final Atlas? atlas;
  final SpineWidgetController controller;
  final BoxFit fit;
  final Alignment alignment;
  final BoundsProvider boundsProvider;
  final bool sizedByBounds;

  const SpineWidget.asset(this.skeletonFile, this.atlasFile, this.controller, {BoxFit? fit, Alignment? alignment, BoundsProvider? boundsProvider, bool? sizedByBounds, super.key})
      : _assetType = AssetType.Asset,
        fit = fit ?? BoxFit.contain,
        alignment = alignment ?? Alignment.center,
        boundsProvider = boundsProvider ?? const SetupPoseBounds(),
        sizedByBounds = sizedByBounds ?? false,
        skeletonData = null,
        atlas = null;

  const SpineWidget.file(this.skeletonFile, this.atlasFile, this.controller, {BoxFit? fit, Alignment? alignment, BoundsProvider? boundsProvider, bool? sizedByBounds, super.key})
      : _assetType = AssetType.File,
        fit = fit ?? BoxFit.contain,
        alignment = alignment ?? Alignment.center,
        boundsProvider = boundsProvider ?? const SetupPoseBounds(),
        sizedByBounds = sizedByBounds ?? false,
        skeletonData = null,
        atlas = null;

  const SpineWidget.http(this.skeletonFile, this.atlasFile, this.controller, {BoxFit? fit, Alignment? alignment, BoundsProvider? boundsProvider, bool? sizedByBounds, super.key})
      : _assetType = AssetType.Http,
        fit = fit ?? BoxFit.contain,
        alignment = alignment ?? Alignment.center,
        boundsProvider = boundsProvider ?? const SetupPoseBounds(),
        sizedByBounds = sizedByBounds ?? false,
        skeletonData = null,
        atlas = null;

  const SpineWidget.raw(this.skeletonData, this.atlas, this.controller, {BoxFit? fit, Alignment? alignment, BoundsProvider? boundsProvider, bool? sizedByBounds, super.key})
      : _assetType = AssetType.Raw,
        fit = fit ?? BoxFit.contain,
        alignment = alignment ?? Alignment.center,
        boundsProvider = boundsProvider ?? const SetupPoseBounds(),
        sizedByBounds = sizedByBounds ?? false,
        skeletonFile = null,
        atlasFile = null;

  @override
  State<SpineWidget> createState() => _SpineWidgetState();
}

class _SpineWidgetState extends State<SpineWidget> {
  SkeletonDrawable? skeletonDrawable;

  @override
  void initState() {
    super.initState();
    if (widget._assetType == AssetType.Raw) {
      loadRaw(widget.skeletonData!, widget.atlas!);
    } else {
      loadFromAsset(widget.skeletonFile!, widget.atlasFile!, widget._assetType);
    }
  }

  void loadRaw(SkeletonData skeletonData, Atlas atlas) {
    skeletonDrawable = SkeletonDrawable(atlas, skeletonData, false);
    skeletonDrawable?.update(0);
  }

  void loadFromAsset(String skeletonFile, String atlasFile, AssetType assetType) async {
    late Atlas atlas;
    late SkeletonData skeletonData;

    switch (assetType) {
      case AssetType.Asset:
        atlas = await Atlas.fromAsset(rootBundle, atlasFile);
        skeletonData = skeletonFile.endsWith(".json")
            ? SkeletonData.fromJson(atlas, await rootBundle.loadString(skeletonFile))
            : SkeletonData.fromBinary(atlas, (await rootBundle.load(skeletonFile)).buffer.asUint8List());
        break;
      case AssetType.File:
        atlas = await Atlas.fromFile(atlasFile);
        skeletonData = skeletonFile.endsWith(".json")
            ? SkeletonData.fromJson(atlas, utf8.decode(await File(skeletonFile).readAsBytes()))
            : SkeletonData.fromBinary(atlas, await File(skeletonFile).readAsBytes());
        break;
      case AssetType.Http:
        atlas = await Atlas.fromUrl(atlasFile);
        skeletonData = skeletonFile.endsWith(".json")
            ? SkeletonData.fromJson(atlas, utf8.decode((await http.get(Uri.parse(skeletonFile))).bodyBytes))
            : SkeletonData.fromBinary(atlas, (await http.get(Uri.parse(skeletonFile))).bodyBytes);
        break;
      case AssetType.Raw:
        throw Exception("Raw assets can not be loaded via loadFromAsset().");
    }

    skeletonDrawable = SkeletonDrawable(atlas, skeletonData, true);
    widget.controller._initialize(atlas, skeletonData, skeletonDrawable!);
    skeletonDrawable?.update(0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (skeletonDrawable != null) {
      print("Skeleton loaded, rebuilding painter");
      return _SpineRenderObjectWidget(skeletonDrawable!, widget.fit, widget.alignment, widget.boundsProvider, widget.sizedByBounds);
    } else {
      print("Skeleton not loaded yet");
      return const SizedBox();
    }
  }

  @override
  void dispose() {
    skeletonDrawable?.dispose();
    super.dispose();
  }
}

class _SpineRenderObjectWidget extends LeafRenderObjectWidget {
  final SkeletonDrawable _skeletonDrawable;
  final BoxFit _fit;
  final Alignment _alignment;
  final BoundsProvider _boundsProvider;
  final bool _sizedByBounds;

  _SpineRenderObjectWidget(this._skeletonDrawable, this._fit, this._alignment, this._boundsProvider, this._sizedByBounds);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _SpineRenderObject(_skeletonDrawable, _fit, _alignment, _boundsProvider, _sizedByBounds);
  }

  @override
  void updateRenderObject(BuildContext context, covariant _SpineRenderObject renderObject) {
    renderObject.skeletonDrawable = _skeletonDrawable;
    renderObject.fit = _fit;
    renderObject.alignment = _alignment;
    renderObject.boundsProvider = _boundsProvider;
    renderObject.sizedByBounds = _sizedByBounds;
  }
}

class _SpineRenderObject extends RenderBox {
  SkeletonDrawable _skeletonDrawable;
  double _deltaTime = 0;
  final Stopwatch _stopwatch = Stopwatch();
  BoxFit _fit;
  Alignment _alignment;
  BoundsProvider _boundsProvider;
  bool _sizedByBounds;
  Bounds _bounds;
  _SpineRenderObject(this._skeletonDrawable, this._fit, this._alignment, this._boundsProvider, this._sizedByBounds): _bounds = _boundsProvider.computeBounds(_skeletonDrawable);

  set skeletonDrawable(SkeletonDrawable skeletonDrawable) {
    if (_skeletonDrawable == skeletonDrawable) return;

    _skeletonDrawable = skeletonDrawable;
    _bounds = _boundsProvider.computeBounds(_skeletonDrawable);
    markNeedsLayout();
    markNeedsPaint();
  }

  BoxFit get fit => _fit;

  set fit(BoxFit fit) {
    if (fit != _fit) {
      _fit = fit;
      markNeedsLayout();
      markNeedsPaint();
    }
  }

  Alignment get alignment => _alignment;

  set alignment(Alignment alignment) {
    if (alignment != _alignment) {
      _alignment = alignment;
      markNeedsLayout();
      markNeedsPaint();
    }
  }

  BoundsProvider get boundsProvider => _boundsProvider;

  set boundsProvider(BoundsProvider boundsProvider) {
    if (boundsProvider != _boundsProvider) {
      _boundsProvider = boundsProvider;
      _bounds = boundsProvider.computeBounds(_skeletonDrawable);
      markNeedsLayout();
      markNeedsPaint();
    }
  }

  bool get sizedByBounds => _sizedByBounds;

  set sizedByBounds(bool sizedByBounds) {
    if (sizedByBounds != _sizedByBounds) {
      _sizedByBounds = _sizedByBounds;
      markNeedsLayout();
      markNeedsPaint();
    }
  }

  @override
  bool get sizedByParent => !_sizedByBounds;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  double computeMinIntrinsicWidth(double height) {
    return _computeConstrainedSize(BoxConstraints.tightForFinite(height: height)).width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return _computeConstrainedSize(BoxConstraints.tightForFinite(height: height)).width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _computeConstrainedSize(BoxConstraints.tightForFinite(width: width)).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _computeConstrainedSize(BoxConstraints.tightForFinite(width: width)).height;
  }

  // Called when not sizedByParent, uses the intrinsic width/height for sizing, while trying to retain aspect ratio.
  @override
  void performLayout() {
    if (!sizedByParent) size = _computeConstrainedSize(constraints);
  }

  // Called when sizedByParent, we want to go as big as possible.
  @override
  void performResize() {
    size = constraints.biggest;
  }

  Size _computeConstrainedSize(BoxConstraints constraints) {
    return sizedByParent ? constraints.smallest : constraints.constrainSizeAndAttemptToPreserveAspectRatio(Size(_bounds.width, _bounds.height));
  }

  @override
  void attach(rendering.PipelineOwner owner) {
    super.attach(owner);
    _stopwatch.start();
  }

  @override
  void detach() {
    _stopwatch.stop();
    super.detach();
  }

  void _beginFrame(Duration duration) {
    _deltaTime = _stopwatch.elapsedTicks / _stopwatch.frequency;
    _stopwatch.reset();
    _stopwatch.start();
    _skeletonDrawable.update(_deltaTime);
    markNeedsPaint();
  }

  void _setCanvasTransform(Canvas canvas, Offset offset) {
    final double x = -_bounds.x - _bounds.width / 2.0 - (_alignment.x * _bounds.width / 2.0);
    final double y = -_bounds.y - _bounds.height / 2.0 - (_alignment.y * _bounds.height / 2.0);
    double scaleX = 1.0, scaleY = 1.0;

    switch (_fit) {
      case BoxFit.fill:
        scaleX = size.width / _bounds.width;
        scaleY = size.height / _bounds.height;
        break;
      case BoxFit.contain:
        scaleX = scaleY = min(size.width / _bounds.width, size.height / _bounds.height);
        break;
      case BoxFit.cover:
        scaleX = scaleY = max(size.width / _bounds.width, size.height / _bounds.height);
        break;
      case BoxFit.fitHeight:
        scaleX = scaleY = size.height / _bounds.height;
        break;
      case BoxFit.fitWidth:
        scaleX = scaleY = size.width / _bounds.width;
        break;
      case BoxFit.none:
        scaleX = scaleY = 1.0;
        break;
      case BoxFit.scaleDown:
        final double scale = min(size.width / _bounds.width, size.height / _bounds.height);
        scaleX = scaleY = scale < 1.0 ? scale : 1.0;
        break;
    }

    canvas
      ..translate(
          offset.dx + size.width / 2.0 + (_alignment.x * size.width / 2.0),
          offset.dy + size.height / 2.0 + (_alignment.y * size.height / 2.0))
      ..scale(scaleX, scaleY)
      ..translate(x, y);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas
      ..save()
      ..clipRect(offset & size);

    canvas.save();
    _setCanvasTransform(canvas, offset);

    final commands = _skeletonDrawable.render();
    for (final cmd in commands) {
      canvas.drawVertices(
          cmd.vertices, rendering.BlendMode.modulate, _skeletonDrawable.atlas.atlasPagePaints[cmd.atlasPageIndex]);
    }

    canvas.restore();
    SchedulerBinding.instance.scheduleFrameCallback(_beginFrame);
  }
}
