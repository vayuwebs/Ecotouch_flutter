import 'dart:io';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class ExportService {
  static const String _dateTimeFormat = 'yyyy-MM-dd HH:mm';

  /// Get default save path (Downloads)
  Future<String> _getDefaultSavePath(String fileName) async {
    final directory = await getDownloadsDirectory();
    // Fallback to documents if downloads is null (less likely on Windows)
    final path =
        directory?.path ?? (await getApplicationDocumentsDirectory()).path;
    return '$path${Platform.pathSeparator}$fileName';
  }

  /// Sanitize filename to remove illegal characters
  String _sanitizeFileName(String fileName) {
    // Replace invalid characters with underscore
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(' ', '_');
  }

  /// Export data to Excel
  Future<String> exportToExcel({
    required String title,
    required List<String> headers,
    required List<List<dynamic>> data,
    String? sheetName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName ?? 'Sheet1'];

    // Add Title
    sheet.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("D1"),
        customValue: TextCellValue(title));
    final titleCell = sheet.cell(CellIndex.indexByString("A1"));
    titleCell.value = TextCellValue(title);
    titleCell.cellStyle = CellStyle(
        bold: true, fontSize: 16, horizontalAlign: HorizontalAlign.Center);

    // Add Headers
    for (var i = 0; i < headers.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(bold: true);
    }

    // Add Data
    for (var rowIdx = 0; rowIdx < data.length; rowIdx++) {
      final row = data[rowIdx];
      for (var colIdx = 0; colIdx < row.length; colIdx++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
            columnIndex: colIdx, rowIndex: rowIdx + 3));
        final value = row[colIdx];
        if (value is num) {
          cell.value = DoubleCellValue(value.toDouble());
        } else {
          cell.value = TextCellValue(value.toString());
        }
      }
    }

    // Save File
    final String timestamp =
        DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final String sanitizedTitle = _sanitizeFileName(title);
    final String fileName = '${sanitizedTitle}_$timestamp.xlsx';

    String? outputFile;
    try {
      // For Desktop (Windows) use FilePicker to save
      outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel File',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        lockParentWindow: true, // Try locking parent window
      );
    } catch (e) {
      print('FilePicker failed: $e');
    }

    // Fallback: Save to Downloads/Documents if picker failed or cancelled (assuming failed if user says it didn't open)
    // Determining if it was cancellation vs failure is hard, but we can verify if file exists.
    // If outputFile is null, we'll auto-save to ensure the user gets the file.

    if (outputFile == null) {
      outputFile = await _getDefaultSavePath(fileName);
    } else {
      if (!outputFile.endsWith('.xlsx')) outputFile += '.xlsx';
    }

    final file = File(outputFile);
    await file.writeAsBytes(excel.save()!);
    return outputFile;
  }

  /// Export data to PDF
  Future<String> exportToPdf({
    required String title,
    required List<String> headers,
    required List<List<dynamic>> data,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
                level: 0,
                child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(title,
                          style: pw.TextStyle(
                              fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          DateFormat(_dateTimeFormat).format(DateTime.now())),
                    ])),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: headers,
              data: data
                  .map((row) => row.map((e) => e.toString()).toList())
                  .toList(),
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellHeight: 30,
              cellAlignments: {
                // Default alignment can be tweaked if needed
                for (var i = 0; i < headers.length; i++)
                  i: pw.Alignment.centerLeft,
              },
            ),
          ];
        },
      ),
    );

    final String timestamp =
        DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final String sanitizedTitle = _sanitizeFileName(title);
    final String fileName = '${sanitizedTitle}_$timestamp.pdf';

    String? outputFile;
    try {
      outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF File',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        lockParentWindow: true,
      );
    } catch (e) {
      print('FilePicker failed: $e');
    }

    if (outputFile == null) {
      outputFile = await _getDefaultSavePath(fileName);
    } else {
      if (!outputFile.endsWith('.pdf')) outputFile += '.pdf';
    }

    final file = File(outputFile);
    await file.writeAsBytes(await pdf.save());
    return outputFile;
  }
}
