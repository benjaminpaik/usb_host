import 'dart:math';
import 'package:flutter/material.dart';

class PlotData {
  final _xTickTimes = <double>[];
  List<PlotCurve> curves;
  int _selectedIndex = 0;

  Color backgroundColor;
  int xSegments;
  int ySegments;
  int tickWidth;
  double tickLength;
  bool _updatePlots = true;

  TextPainter textPainter =
      TextPainter(textAlign: TextAlign.left, textDirection: TextDirection.ltr);

  PlotData(this.curves,
      {this.backgroundColor = Colors.white,
      this.xSegments = 4,
      this.ySegments = 4,
      this.tickWidth = 1,
      this.tickLength = 4});

  bool get updatePlots {
    return _updatePlots;
  }

  set displaySelected(bool displayed) {
    curves[_selectedIndex].displayed = displayed;
  }

  bool get displaySelected {
    return curves[_selectedIndex].displayed;
  }

  set selectedState(String name) {
    final curveNames = curves.map((e) => e._name).toList();
    final curveIndex = curveNames.indexOf(name);

    if (curveIndex >= 0) {
      _selectedIndex = curveIndex;
    }
  }

  String get selectedState {
    return curves[_selectedIndex].name;
  }

  void resetSamples() {
    for (var element in curves) {
      element._resetSamples();
    }
  }

  void updateSamples(double time) {
    for (var element in curves) {
      element._updateSample(time);
    }
  }

  void _saveSamples() {
    for (var element in curves) {
      element._saveSamples();
    }
  }

  void saveXTickTimes(Size size, PlotCurve state) {
    _xTickTimes.clear();
    for (int i = 1; i <= xSegments; i++) {
      final xTickIncrement = size.width / xSegments;
      final xTick = xTickIncrement * i;
      _xTickTimes.add(state._getTickTime(size.width, xTick));
    }
  }
}

class PlotCurve {
  final String _name;
  final _points = <Point<double>>[];
  var _savedPoints = <Point<double>>[];
  final double _maxValue, _minValue, _dataRange;
  double _timeReference = 0.0;
  int _maxSamples = 100;
  double _timeSpan = 5.0;

  double _value = 0;
  bool displayed = true;

  final Paint _paint = Paint()
    ..color = Colors.red
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  PlotCurve(this._name, this._maxValue, this._minValue,
      {Color color = Colors.red})
      : _dataRange = _maxValue - _minValue {
    _paint.color = color;
  }

  set color(Color color) {
    _paint.color = color;
  }

  Color get color {
    return _paint.color;
  }

  set strokeWidth(double width) {
    _paint.strokeWidth = width;
  }

  String get name {
    return _name;
  }

  set value(double input) {
    _value = input;
  }

  void updateTimeScaling(int maxSamples, double timeSpan) {
    _maxSamples = maxSamples;
    _timeSpan = timeSpan;
  }

  void _updateTimeReference(List<Point<double>> points) {
    _timeReference = points.first.x;
  }

  double _getTickTime(double width, double x) {
    return ((x / width) * _timeSpan) + _timeReference;
  }

  double _getTickValue(double height, double y) {
    return (((height - y) / height) * _dataRange) + _minValue;
  }

  double _getScaledTime(double width, double time) {
    return ((time - _timeReference) / _timeSpan) * width;
  }

  double _getScaledValue(double height, double value) {
    return ((_maxValue - value) / (_maxValue - _minValue)) * height;
  }

  void _updateSample(double time) {
    _points.add(Point<double>(time, _value));
    if (_points.length > _maxSamples) {
      _points.removeAt(0);
    }
  }

  void _saveSamples() {
    _savedPoints = List<Point<double>>.from(_points);
  }

  void _resetSamples() {
    _points.clear();
  }
}

class Oscilloscope extends StatefulWidget {
  final PlotData plotData;

  const Oscilloscope({required key, required this.plotData}) : super(key: key);

  @override
  OscilloscopeState createState() => OscilloscopeState();
}

class OscilloscopeState extends State<Oscilloscope>
    with WidgetsBindingObserver {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (TapDownDetails _) {
        widget.plotData._updatePlots = !widget.plotData._updatePlots;
        if (widget.plotData._updatePlots) {
          widget.plotData.resetSamples();
        } else {
          widget.plotData._saveSamples();
        }
      },
      child: Container(
          color: widget.plotData.backgroundColor,
          child: CustomPaint(
            painter: _PlotPainter(widget.plotData),
            child: Container(),
          )),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.plotData.resetSamples();
    }
  }
}

class _PlotPainter extends CustomPainter {
  final PlotData _plotData;

  _PlotPainter(this._plotData);

  void generateXTicks(Canvas canvas, Path path, Size size, PlotCurve state) {
    final xTickIncrement = size.width / _plotData.xSegments;
    final yTickStart = (size.height - _plotData.tickLength) / 2;
    final yTickEnd = yTickStart + _plotData.tickLength;

    if (_plotData._updatePlots) {
      _plotData.saveXTickTimes(size, state);
    }

    for (int i = 0; i < _plotData.xSegments; i++) {
      double xTick = xTickIncrement * (i + 1);
      path.moveTo(xTick, yTickStart);
      path.lineTo(xTick, yTickEnd);

      canvas.save();
      _plotData.textPainter.text = TextSpan(
          style: TextStyle(color: state._paint.color),
          text: _plotData._xTickTimes[i].toStringAsFixed(1));

      canvas.translate(xTick, yTickStart);
      canvas.rotate(pi / 2);
      _plotData.textPainter.layout();
      _plotData.textPainter.paint(canvas, const Offset(20, 0));
      canvas.restore();
    }
  }

  void generateYTicks(Canvas canvas, Path path, Size size, PlotCurve state) {
    final yTickIncrement = size.height / _plotData.ySegments;

    for (int i = 1; i < _plotData.ySegments; i++) {
      double yTick = yTickIncrement * i;
      path.moveTo(0, yTick);
      path.lineTo(_plotData.tickLength, yTick);

      _plotData.textPainter.text = TextSpan(
          style: TextStyle(color: state._paint.color),
          text: state._getTickValue(size.height, yTick).toStringAsFixed(2));
      _plotData.textPainter.layout();
      _plotData.textPainter.paint(canvas, Offset(10, yTick));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    const minPoints = 2;
    final series = _plotData.curves;
    if (series.isNotEmpty) {
      // add each data series
      for (var state in series) {
        if (state.displayed) {
          final path = Path();
          final points =
              _plotData._updatePlots ? state._points : state._savedPoints;
          if (points.length > minPoints) {
            state._updateTimeReference(points);

            // initialize the first data point
            final startTime = state._getScaledTime(size.width, points.first.x);
            final startSample =
                state._getScaledValue(size.height, points.first.y);
            double previousSample = startSample;
            path.moveTo(startTime, startSample);

            // add remaining data points
            points.sublist(1, points.length).forEach((dataPoint) {
              final scaledTime = state._getScaledTime(size.width, dataPoint.x);
              final scaledValue =
                  state._getScaledValue(size.height, dataPoint.y);

              if (scaledValue > size.height) {
                if (previousSample < size.height) {
                  path.lineTo(scaledTime, size.height);
                }
                path.moveTo(scaledTime, size.height);
              } else if (scaledValue < 0) {
                if (previousSample > 0) {
                  path.lineTo(scaledTime, 0);
                }
                path.moveTo(scaledTime, 0);
              } else {
                path.lineTo(scaledTime, scaledValue);
              }
              previousSample = scaledValue;
            });

            if (state == _plotData.curves[_plotData._selectedIndex]) {
              generateXTicks(canvas, path, size, state);
              generateYTicks(canvas, path, size, state);
            }
            // render the data on the canvas
            canvas.drawPath(path, state._paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

Color invert(Color color) {
  return Color.from(
      alpha: color.a,
      red: 1.0 - color.r,
      green: 1.0 - color.g,
      blue: 1.0 - color.b);
}
