import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:blue_print_pos/models/batch_print_options.dart';
import 'package:blue_print_pos/models/models.dart';
import 'package:blue_print_pos/receipt/receipt_section_text.dart';
import 'package:blue_print_pos/scanner/blue_scanner.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as blue_thermal;
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue;
import 'package:flutter_blue_plus/gen/flutterblueplus.pb.dart' as proto;
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
//import 'package:esc_pos_utils_plus/esc_pos_utils.dart';

class BluePrintPos {
  BluePrintPos._() {
    _bluetoothAndroid = blue_thermal.BlueThermalPrinter.instance;
    _bluetoothIOS = flutter_blue.FlutterBluePlus.instance;
  }

  static BluePrintPos get instance => BluePrintPos._();

  static const MethodChannel _channel = MethodChannel('blue_print_pos');

  /// This field is library to handle in Android Platform
  blue_thermal.BlueThermalPrinter? _bluetoothAndroid;

  /// This field is library to handle in iOS Platform
  flutter_blue.FlutterBluePlus? _bluetoothIOS;

  /// Bluetooth Device model for iOS
  flutter_blue.BluetoothDevice? _bluetoothDeviceIOS;

  /// State to get bluetooth is connected
  bool _isConnected = false;

  /// Getter value [_isConnected]
  bool get isConnected => _isConnected;

  /// Selected device after connecting
  BlueDevice? selectedDevice;

  /// return bluetooth device list, handler Android and iOS in [BlueScanner]
  Future<List<BlueDevice>> scan() async {
    return await BlueScanner.scan();
  }

  /// When connecting, reassign value [selectedDevice] from parameter [device]
  /// and if connection time more than [timeout]
  /// will return [ConnectionStatus.timeout]
  /// When connection success, will return [ConnectionStatus.connected]
  Future<ConnectionStatus> connect(
    BlueDevice device, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    selectedDevice = device;
    try {
      if (Platform.isAndroid) {
        final blue_thermal.BluetoothDevice bluetoothDeviceAndroid =
            blue_thermal.BluetoothDevice(
                selectedDevice?.name ?? '', selectedDevice?.address ?? '');
        await _bluetoothAndroid?.connect(bluetoothDeviceAndroid);
      } else if (Platform.isIOS) {
        _bluetoothDeviceIOS = flutter_blue.BluetoothDevice.fromProto(
          proto.BluetoothDevice(
            name: selectedDevice?.name ?? '',
            remoteId: selectedDevice?.address ?? '',
            type: proto.BluetoothDevice_Type.valueOf(selectedDevice?.type ?? 0),
          ),
        );
        final List<flutter_blue.BluetoothDevice> connectedDevices =
            await _bluetoothIOS?.connectedDevices ??
                <flutter_blue.BluetoothDevice>[];
        final int deviceConnectedIndex = connectedDevices
            .indexWhere((flutter_blue.BluetoothDevice bluetoothDevice) {
          return bluetoothDevice.id == _bluetoothDeviceIOS?.id;
        });
        if (deviceConnectedIndex < 0) {
          await _bluetoothDeviceIOS?.connect();
        }
      }

      _isConnected = true;
      selectedDevice?.connected = true;
      return Future<ConnectionStatus>.value(ConnectionStatus.connected);
    } on Exception catch (error) {
      print('$runtimeType - Error $error');
      _isConnected = false;
      selectedDevice?.connected = false;
      return Future<ConnectionStatus>.value(ConnectionStatus.timeout);
    }
  }

  /// To stop communication between bluetooth device and application
  Future<ConnectionStatus> disconnect({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (Platform.isAndroid) {
      if (await _bluetoothAndroid?.isConnected ?? false) {
        await _bluetoothAndroid?.disconnect();
      }
      _isConnected = false;
    } else if (Platform.isIOS) {
      await _bluetoothDeviceIOS?.disconnect();
      _isConnected = false;
    }

    return ConnectionStatus.disconnect;
  }

  /// This method only for print text
  /// value and styling inside model [ReceiptSectionText].
  /// [feedCount] to create more space after printing process done
  ///
  /// [useCut] to cut printing process
  ///
  /// [duration] the delay duration before converting the html to bytes.
  /// defaults to 0.
  ///
  /// [textScaleFactor] the text scale factor (must be > 0 or null).
  /// note that this currently only works on Android.
  /// defaults to system's font settings.
  Future<void> printReceiptText(
    ReceiptSectionText receiptSectionText, {
    int feedCount = 0,
    bool useCut = false,
    bool useRaster = false,
    double duration = 0,
    PaperSize paperSize = PaperSize.mm58,
    double? textScaleFactor,
    BatchPrintOptions? batchPrintOptions,
  }) async {
    final int contentLength = receiptSectionText.contentLength;

    final BatchPrintOptions batchOptions;
    if (batchPrintOptions != null) {
      batchOptions = batchPrintOptions;
    } else {
      if (Platform.isIOS) {
        batchOptions = const BatchPrintOptions.perNContent(20);
      } else {
        batchOptions = BatchPrintOptions.full;
      }
    }

    final Iterable<List<int>> startEndIter =
        batchOptions.getStartEnd(contentLength);

    for (final List<int> startEnd in startEndIter) {
      final ReceiptSectionText section = receiptSectionText.getSection(
        startEnd[0],
        startEnd[1],
      );
      // This is to prevent cropped section at the bottom
      if (Platform.isIOS) {
        section.addSpacerPx(15);
      }
      final Uint8List bytes = await contentToImage(
        content: section.getContent(),
        duration: duration,
        textScaleFactor: textScaleFactor,
      );
      List<int>? croppedExcessTop;
      // This is to remove the excess top
      if (Platform.isIOS) {
        final img.Image? image = img.decodeImage(bytes);
        if (image != null) {
          final img.Image cropped = img.copyCrop(
            image,
            0,
            45,
            image.width,
            image.height - 45,
          );
          croppedExcessTop = img.encodeJpg(cropped);
        }
      }
      final List<int> byteBuffer = await _getBytes(
        croppedExcessTop ?? bytes,
        paperSize: paperSize,
        feedCount: feedCount,
        useCut: useCut,
        useRaster: useRaster,
      );
      await _printProcess(byteBuffer);
      log(
        'start: ${startEnd[0]} end: ${startEnd[1]}',
        name: 'BluePrintPos.printReceiptText',
      );

      if (batchOptions.delay != Duration.zero &&
          !batchOptions.delay.isNegative) {
        await Future<void>.delayed(batchOptions.delay);
      }
    }
  }

  /// This method only for print image with parameter [bytes] in List<int>
  /// define [width] to custom width of image, default value is 120
  /// [feedCount] to create more space after printing process done
  /// [useCut] to cut printing process
  Future<void> printReceiptImage(
    List<int> bytes, {
    int width = 120,
    int feedCount = 0,
    bool useCut = false,
    bool useRaster = false,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    final List<int> byteBuffer = await _getBytes(
      bytes,
      customWidth: width,
      feedCount: feedCount,
      useCut: useCut,
      useRaster: useRaster,
      paperSize: paperSize,
    );
    _printProcess(byteBuffer);
  }

  /// This method only for print QR, only pass value on parameter [data]
  /// define [size] to size of QR, default value is 120
  /// [feedCount] to create more space after printing process done
  /// [useCut] to cut printing process
  Future<void> printQR(
    String data, {
    int size = 120,
    int feedCount = 0,
    bool useCut = false,
  }) async {
    final List<int> byteBuffer = await _getQRImage(data, size.toDouble());
    printReceiptImage(
      byteBuffer,
      width: size,
      feedCount: feedCount,
      useCut: useCut,
    );
  }

  Future<void> printBarcode(
      List<dynamic> bytes, {
        int width = 120,
        int feedCount = 0,
        bool useCut = false,
        bool useRaster = false,
        PaperSize paperSize = PaperSize.mm58,
      }) async {
    final List<int> byteBuffer = await _getBytes2(
      bytes,
      customWidth: width,
      feedCount: feedCount,
      useCut: useCut,
      useRaster: useRaster,
      paperSize: paperSize,
    );
    _printProcess(byteBuffer);
  }


  /// Reusable method for print text, image or QR based value [byteBuffer]
  /// Handler Android or iOS will use method writeBytes from ByteBuffer
  /// But in iOS more complex handler using service and characteristic
  Future<void> _printProcess(List<int> byteBuffer) async {
    try {
      if (selectedDevice == null) {
        print('$runtimeType - Device not selected');
        return Future<void>.value(null);
      }
      if (!_isConnected && selectedDevice != null) {
        await connect(selectedDevice!);
      }
      if (Platform.isAndroid) {
        await _bluetoothAndroid?.writeBytes(Uint8List.fromList(byteBuffer));
      } else if (Platform.isIOS) {
        final List<flutter_blue.BluetoothService> bluetoothServices =
            await _bluetoothDeviceIOS?.discoverServices() ??
                <flutter_blue.BluetoothService>[];
        final flutter_blue.BluetoothService bluetoothService =
            bluetoothServices.firstWhere(
          (flutter_blue.BluetoothService service) => service.isPrimary,
        );
        final flutter_blue.BluetoothCharacteristic characteristic =
            bluetoothService.characteristics.firstWhere(
          (flutter_blue.BluetoothCharacteristic bluetoothCharacteristic) =>
              bluetoothCharacteristic.properties.write,
        );
        await characteristic.write(byteBuffer, withoutResponse: true);
      }
    } on Exception catch (error) {
      print('$runtimeType - Error $error');
    }
  }

  /// This method to convert byte from [data] into as image canvas.
  /// It will automatically set width and height based [paperSize].
  /// [customWidth] to print image with specific width
  /// [feedCount] to generate byte buffer as feed in receipt.
  /// [useCut] to cut of receipt layout as byte buffer.
  Future<List<int>> _getBytes(
    List<int> data, {
    PaperSize paperSize = PaperSize.mm58,
    int customWidth = 0,
    int feedCount = 0,
    bool useCut = false,
    bool useRaster = false,
  }) async {
    List<int> bytes = <int>[];
    final CapabilityProfile profile = await CapabilityProfile.load();
    final Generator generator = Generator(paperSize, profile);
    final img.Image _resize = img.copyResize(
      img.decodeImage(data)!,
      width: customWidth > 0 ? customWidth : paperSize.width,
    );
    if (useRaster) {
      bytes += generator.imageRaster(_resize);
    } else {
      bytes += generator.image(_resize);
    }
    if (feedCount > 0) {
      bytes += generator.feed(feedCount);
    }
    if (useCut) {
      bytes += generator.cut();
    }
    return bytes;
  }

  Future<List<int>> _getBytes2(
      List<dynamic> data, {
        PaperSize paperSize = PaperSize.mm58,
        int customWidth = 120,
        int feedCount = 0,
        bool useCut = false,
        bool useRaster = false,
      }) async {
    List<int> bytes = <int>[];
    final CapabilityProfile profile = await CapabilityProfile.load();
    final Generator generator = Generator(paperSize, profile);

    print("data");
    print(data);
    print(bytes);
    bytes += generator.barcode(Barcode.code128(data), height: 60 );
    print(bytes);
    if(feedCount > 0 ){
      bytes += generator.feed(feedCount);
    }
    if (useCut) {
      bytes += generator.cut();
    }

    return bytes;
  }

  /// Handler to generate QR image from [text] and set the [size].
  /// Using painter and convert to [Image] object and return as [Uint8List]
  Future<Uint8List> _getQRImage(String text, double size) async {
    try {
      final Image image = await QrPainter(
        data: text,
        version: QrVersions.auto,
        gapless: false,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
      ).toImage(size);
      final ByteData? byteData =
          await image.toByteData(format: ImageByteFormat.png);
      assert(byteData != null);
      return byteData!.buffer.asUint8List();
    } on Exception catch (exception) {
      print('$runtimeType - $exception');
      rethrow;
    }
  }

  /// Converts HTML content to bytes
  ///
  /// [content] the html text
  ///
  /// [duration] the delay duration before converting the html to bytes.
  /// defaults to 0.
  ///
  /// [textScaleFactor] the text scale factor (must be > 0 or null).
  /// note that this currently only works on Android.
  /// defaults to system's font settings.
  static Future<Uint8List> contentToImage({
    required String content,
    double duration = 0,
    double? textScaleFactor,
  }) async {
    assert(
      textScaleFactor == null || textScaleFactor > 0,
      '`textScaleFactor` must be either null or more than zero.',
    );
    final Map<String, dynamic> arguments = <String, dynamic>{
      'content': content,
      'duration': Platform.isIOS ? 2000 : duration,
      'textScaleFactor': textScaleFactor,
    };
    Uint8List results = Uint8List.fromList(<int>[]);
    try {
      results = await _channel.invokeMethod('contentToImage', arguments) ??
          Uint8List.fromList(<int>[]);
    } on Exception catch (e) {
      log('[method:contentToImage]: $e');
      throw Exception('Error: $e');
    }
    return results;
  }
}
