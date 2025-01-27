import 'collection_style.dart';
import 'receipt_alignment.dart';
import 'receipt_text_size_type.dart';
import 'receipt_text_style.dart';
import 'receipt_text_style_type.dart';

class ReceiptItemListing {

  ReceiptItemListing(
      this.itemList, this.maxChar
      );

  // The outer list is the list of items
  // The inner list (inner) represents a single item
  // inner[0] = Description
  // inner[1] = UOM
  // inner[2] = Qty
  final List<List<String>> itemList;
  final int maxChar;

  String generateRows(){
    String result = "";
    String extended = '''
    <tr>
      <td></td>
      <td>Item 1</td>
      <td></td>
      <td></td>
    </tr>
    ''';

    int index = 1;
    for(List<String> item in itemList){
      int totalLength = item.join().length;
      if(totalLength <= maxChar){
         result+='''
          <tr>
            <td align= "left" width="10%">${index.toString()}</td>
            <td align= "left" width="60%">${item[0]}</td>
            <td align= "left" width="10%">${item[1]}</td>
            <td align= "left" width="20%">${item[2]}</td>
          </tr>
          ''';
      }
      else{
        int descLength = maxChar - index.toString().length - item[1].length - item[2].length;
        int iter = (item[0].length/descLength).floor();
        int start = 0;

        for (int i=0;i<iter;i++){
          if(i==0){
            result+='''
            <tr>
              <td align= "left" width="10%">${index.toString()}</td>
              <td align= "left" width="60%">${item[0].substring(start,start+descLength)}</td>
              <td align= "left" width="10%">${item[1]}</td>
              <td align= "left" width="20%">${item[2]}</td>
            </tr>
            ''';
          }
          else{
            result+='''
          <tr>
            <td align= "left" width="10%"></td>
            <td align= "left" width="60%">${item[0].substring(start,start+descLength)}</td>
            <td align= "left" width="10%"></td>
            <td align= "left" width="20%"></td>
          </tr>
          ''';
          }

          start+=descLength;
        }

        result+='''
          <tr>
            <td align= "left" width="10%"></td>
            <td align= "left" width="60%">${item[0].substring(start,item[0].length)}</td>
            <td align= "left" width="10%"></td>
            <td align= "left" width="20%"></td>
          </tr>
          ''';
      }
      index += 1;
    }

    return result;
  }

  String get html => '''
    <style>
      table {
        border-collapse: collapse;
      }
      th{
        border-bottom-style: dashed;
        padding-right: 10px;
      }
      td{
        text-align: left;
        padding-right: 10px;
      }
    </style>
     <table>
      <tr>
        <th align= "left" width="10%">No</th>
        <th align= "left" width="60%">Description</th>
        <th align= "left" width="10%">UOM</th>
        <th align= "left" width="20%">Qty</th>
      </tr>
    '''
      +generateRows()
      + '''</table>''';

}
