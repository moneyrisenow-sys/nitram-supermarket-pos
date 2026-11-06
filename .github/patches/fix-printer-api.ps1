$ErrorActionPreference = 'Stop'
$mainPath = Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT/src-tauri/src/main.rs'
$source = Get-Content -LiteralPath $mainPath -Raw
$replacement = @'
#[tauri::command]
fn print_receipt(text:String)->Result<String,String>{
 #[cfg(windows)] {
  use std::{ffi::c_void,ptr::null_mut};
  type PrinterHandle=*mut c_void;
  #[repr(C)] struct DocInfo1W { pDocName:*mut u16, pOutputFile:*mut u16, pDatatype:*mut u16 }
  #[link(name="winspool")]
  unsafe extern "system" {
   fn GetDefaultPrinterW(name:*mut u16, needed:*mut u32)->i32;
   fn OpenPrinterW(name:*const u16, handle:*mut PrinterHandle, defaults:*mut c_void)->i32;
   fn ClosePrinter(handle:PrinterHandle)->i32;
   fn StartDocPrinterW(handle:PrinterHandle, level:u32, info:*const c_void)->u32;
   fn StartPagePrinter(handle:PrinterHandle)->i32;
   fn WritePrinter(handle:PrinterHandle, buffer:*const c_void, count:u32, written:*mut u32)->i32;
   fn EndPagePrinter(handle:PrinterHandle)->i32;
   fn EndDocPrinter(handle:PrinterHandle)->i32;
  }
  let mut needed=0u32;unsafe{GetDefaultPrinterW(null_mut(),&mut needed);}
  if needed==0{return Err("No default Windows printer is configured. Set POS80 Printer as default.".into())}
  let mut name=vec![0u16;needed as usize];if unsafe{GetDefaultPrinterW(name.as_mut_ptr(),&mut needed)}==0{return Err("Could not read the default printer.".into())}
  let mut printer:PrinterHandle=null_mut();if unsafe{OpenPrinterW(name.as_ptr(),&mut printer,null_mut())}==0{return Err("Could not open the default printer. Check POS80 Printer connection.".into())}
  let doc:Vec<u16>="NITRAM Sales Receipt\0".encode_utf16().collect();let raw:Vec<u16>="RAW\0".encode_utf16().collect();
  let info=DocInfo1W{pDocName:doc.as_ptr() as *mut u16,pOutputFile:null_mut(),pDatatype:raw.as_ptr() as *mut u16};
  let job=unsafe{StartDocPrinterW(printer,1,&info as *const _ as *const c_void)};if job==0{unsafe{ClosePrinter(printer)};return Err("Windows could not start the raw print job.".into())}
  let mut bytes=vec![0x1b,0x40];let safe:String=text.chars().map(|c|if c.is_ascii(){c}else{'?'}).collect();bytes.extend_from_slice(safe.as_bytes());bytes.extend_from_slice(&[10,10,10,10]);
  let mut written=0u32;let page=unsafe{StartPagePrinter(printer)}!=0;let ok=page&&unsafe{WritePrinter(printer,bytes.as_ptr() as *const c_void,bytes.len() as u32,&mut written)}!=0;
  if page{unsafe{EndPagePrinter(printer);}}unsafe{EndDocPrinter(printer);ClosePrinter(printer);}
  if !ok||written as usize!=bytes.len(){return Err("Printer did not accept the complete receipt. Check paper and connection.".into())}
  Ok(format!("Receipt sent directly to {}",String::from_utf16_lossy(&name).trim_end_matches('\0')))
 }
 #[cfg(not(windows))] {let _=text;Err("Direct printing is supported in the Windows desktop app.".into())}
}
'@
$pattern = '(?s)#\[tauri::command\]\s*fn print_receipt\(text:String\)->Result<String,String>\s*\{.*?\n\}'
if (-not [regex]::IsMatch($source,$pattern)) { throw 'Could not locate existing print_receipt function.' }
$source = [regex]::Replace($source,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement },1)
if ($source.Contains('OpenPrinterW,StartDocPrinterW') -or $source.Contains('windows_sys::Win32::Graphics::Printing::{ClosePrinter')) { throw 'Old generated printer imports remain.' }
Set-Content -LiteralPath $mainPath -Value $source -NoNewline -Encoding utf8
Write-Host 'Corrected Winspool declarations and ABI.'
