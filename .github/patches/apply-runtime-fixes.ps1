$ErrorActionPreference='Stop'
$project=Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT'
$appPath=Join-Path $project 'dist/app.js'
$app=Get-Content -LiteralPath $appPath -Raw
$scan=@'
function updateScanSuggestions(){
 const box=document.getElementById('productSuggestions'),input=document.getElementById('scan');if(!box||!input)return;
 const q=String(input.value||'').trim().toLowerCase();if(!q){box.innerHTML='';box.style.display='none';scanMatches=[];return}
 if(q.length<2){box.innerHTML='';box.style.display='none';scanMatches=[];return}
 const products=S.products||[],starts=[],contains=[];
 for(let i=0;i<products.length&&starts.length<15;i++){const p=products[i],n=String(p.name||'').toLowerCase(),c=String(p.barcode||p.id||'').trim().toLowerCase();if(c.startsWith(q)||n.startsWith(q))starts.push(p)}
 if(starts.length<15){for(let i=0;i<products.length&&starts.length+contains.length<15;i++){const p=products[i],n=String(p.name||'').toLowerCase(),c=String(p.barcode||p.id||'').trim().toLowerCase();if(!n.startsWith(q)&&!c.startsWith(q)&&(n.includes(q)||c.includes(q)))contains.push(p)}}
 scanMatches=starts.concat(contains);
 box.innerHTML=scanMatches.length?scanMatches.map(p=>'<button type="button" class="scan-suggestion" onclick="chooseScanProduct(&quot;'+escapeScanHtml(p.id)+'&quot;)" style="width:100%;text-align:left;background:white;border:0;padding:11px 13px;cursor:pointer;border-bottom:1px solid #eef0f3"><b>'+escapeScanHtml(p.name)+'</b><small style="display:block;color:#667085">Barcode: '+escapeScanHtml(p.barcode||p.id)+'</small></button>').join(''):'<div style="padding:12px;color:#667085">No matching products</div>';
 box.style.display='block';
}
'@
$a=$app.IndexOf('function updateScanSuggestions(){');$b=$app.IndexOf('function chooseScanProduct',$a);if($a -lt 0 -or $b -lt 0){throw 'Barcode patch markers missing'};$app=$app.Substring(0,$a)+$scan+$app.Substring($b)
$save=@'
let _nitramSaveRevision=0;_nitramSaveBusy=false,_nitramPendingSave=null,_nitramSaveTimer=null;
function _nitramFlushSave(){
 if(_nitramSaveBusy||!_nitramPendingSave)return;const payload=_nitramPendingSave;_nitramPendingSave=null;_nitramSaveBusy=true;
 const x=new XMLHttpRequest();x.open('POST',window.NITRAM_STORAGE.endpoint+'/state',true);x.setRequestHeader('Authorization','Bearer '+window.NITRAM_STORAGE.token);x.setRequestHeader('Content-Type','application/json');
 x.onload=()=>{_nitramSaveBusy=false;if(x.status>=200&&x.status<300){try{const r=JSON.parse(x.responseText);_nitramSaveRevision=r.revision||(_nitramSaveRevision+1);window.NITRAM_STORAGE.setStatus('Saved to local database · revision '+_nitramSaveRevision)}catch(e){window.NITRAM_STORAGE.setStatus('Saved to local database')}}else{window.NITRAM_STORAGE.setStatus('DATABASE SAVE FAILED — '+(x.responseText||x.statusText),true);_nitramPendingSave=payload}if(_nitramPendingSave)_nitramFlushSave()};
 x.onerror=()=>{_nitramSaveBusy=false;_nitramPendingSave=payload;window.NITRAM_STORAGE.setStatus('DATABASE SAVE FAILED — connection error',true)};x.send(payload);
}
const save=()=>{try{if(_nitramSaveTimer)clearTimeout(_nitramSaveTimer);window.NITRAM_STORAGE.setStatus('Saving to local database…');_nitramSaveTimer=setTimeout(()=>{_nitramPendingSave=JSON.stringify(S);_nitramFlushSave()},35);return true}catch(e){window.NITRAM_STORAGE.setStatus('DATABASE SAVE FAILED — '+String(e.message||e),true);throw e}};
window.addEventListener('beforeunload',()=>{try{if(_nitramSaveTimer)clearTimeout(_nitramSaveTimer);const x=new XMLHttpRequest();x.open('POST',window.NITRAM_STORAGE.endpoint+'/state',false);x.setRequestHeader('Authorization','Bearer '+window.NITRAM_STORAGE.token);x.setRequestHeader('Content-Type','application/json');x.send(JSON.stringify(S))}catch(e){console.error('Final save failed',e)}});
const prod=id=>S.products.find(p=>p.id===id);
'@
$a=$app.IndexOf('let _nitramSaveRevision=0,');$b=$app.IndexOf('// Persist the compacted live catalogue',$a);if($a -lt 0 -or $b -lt 0){throw 'Save patch markers missing'};$app=$app.Substring(0,$a)+$save+$app.Substring($b)
$receipt=@'
function receiptPlainText(s){
 const rows=['NITRAM SUPERMARKET','SALES RECEIPT','------------------------------------------','Receipt No: '+(s.receipt||'-'),'Date: '+(s.date||''),'Served by: '+(s.soldBy||'Unknown'),'------------------------------------------'];
 (s.items||[]).forEach(x=>{rows.push(String(x.name||(prod(x.id)||{}).name||x.id));rows.push('  '+x.qty+' x '+Number(x.price||0).toFixed(2)+'   '+(Number(x.price||0)*Number(x.qty||0)).toFixed(2))});
 rows.push('------------------------------------------','TOTAL: KES '+Number(s.netTotal??s.total??0).toFixed(2),'Payment: '+(s.payment||'-'),'Received: '+(s.received==null?'Not entered':'KES '+Number(s.received).toFixed(2)),'Change: '+(s.change==null?'-':'KES '+Number(s.change).toFixed(2)),'------------------------------------------','eTIMS: DEMO ONLY - NOT A KRA INVOICE',S.receiptFooter||'Thank you for shopping with us!','Please keep this receipt for your records.','','');return rows.join('\n');
}
async function printReceiptDirect(){const s=window._nitramReceiptToPrint;if(!s)return toast('Receipt data is unavailable');const invoke=window.__TAURI__?.core?.invoke;if(!invoke)return toast('Direct printing is available only in the installed NITRAM app');try{toast('Sending receipt to the default Windows printer…');const r=await invoke('print_receipt',{text:receiptPlainText(s)});toast(r||'Receipt sent to printer')}catch(e){console.error(e);toast('Printing failed: '+String(e?.message||e))}}
'@
$app=$app.Replace('function receipt(s){document.getElementById(''modal'').style.display=''grid'';','function receipt(s){window._nitramReceiptToPrint=s;document.getElementById(''modal'').style.display=''grid'';')
$app=$app.Replace('<button class="btn" onclick="window.print()">🖨 Print Receipt</button>','<button class="btn" onclick="printReceiptDirect()">🖨 Print Receipt</button>')
$a=$app.IndexOf('function receipt(s){');if($a -lt 0){throw 'Receipt renderer marker missing'};$app=$app.Substring(0,$a)+$receipt+$app.Substring($a)
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
$htmlPath=Join-Path $project 'dist/index.html';$html=Get-Content -LiteralPath $htmlPath -Raw;$html=$html.Replace('window.NITRAM_STORAGE={','window.NITRAM_STORAGE={endpoint,token:cfg.token,');Set-Content -LiteralPath $htmlPath -Value $html -NoNewline -Encoding utf8
$cargoPath=Join-Path $project 'src-tauri/Cargo.toml';$cargo=Get-Content -LiteralPath $cargoPath -Raw
if(-not $cargo.Contains('windows-sys =')){$cargo += @'

[target.'cfg(windows)'.dependencies]
windows-sys = { version = "0.59", features = ["Win32_Foundation", "Win32_Graphics_Printing"] }
'@}
Set-Content -LiteralPath $cargoPath -Value $cargo -NoNewline -Encoding utf8
$rustPath=Join-Path $project 'src-tauri/src/main.rs';$rust=Get-Content -LiteralPath $rustPath -Raw
if(-not $rust.Contains('fn print_receipt(')){
$printer=@'
#[tauri::command]
fn print_receipt(text:String)->Result<String,String>{
 #[cfg(windows)] {
  use std::ptr::{null,null_mut};
  use windows_sys::Win32::Graphics::Printing::{ClosePrinter,EndDocPrinter,EndPagePrinter,GetDefaultPrinterW,OpenPrinterW,StartDocPrinterW,StartPagePrinter,WritePrinter,DOC_INFO_1W};
  let mut chars=0u32;unsafe{GetDefaultPrinterW(null_mut(),&mut chars);}
  if chars==0{return Err("No default Windows printer is configured. Set POS80 Printer as default.".into())}
  let mut name=vec![0u16;chars as usize];if unsafe{GetDefaultPrinterW(name.as_mut_ptr(),&mut chars)}==0{return Err("Could not read the default printer.".into())}
  let mut printer=null_mut();if unsafe{OpenPrinterW(name.as_mut_ptr(),&mut printer,null())}==0{return Err("Could not open the default printer. Check POS80 Printer connection.".into())}
  let doc:Vec<u16>="NITRAM Sales Receipt\0".encode_utf16().collect();let raw:Vec<u16>="RAW\0".encode_utf16().collect();
  let info=DOC_INFO_1W{pDocName:doc.as_ptr() as *mut u16,pOutputFile:null_mut(),pDatatype:raw.as_ptr() as *mut u16};
  let job=unsafe{StartDocPrinterW(printer,1,&info as *const _ as *const u8)};if job==0{unsafe{ClosePrinter(printer)};return Err("Windows could not start the raw print job.".into())}
  let mut bytes=vec![0x1b,0x40];let safe:String=text.chars().map(|c|if c.is_ascii(){c}else{'?'}).collect();bytes.extend_from_slice(safe.as_bytes());bytes.extend_from_slice(&[10,10,10,10]);
  let mut written=0u32;let ok=unsafe{StartPagePrinter(printer)}!=0&&unsafe{WritePrinter(printer,bytes.as_ptr() as *const _,bytes.len() as u32,&mut written)}!=0;
  unsafe{EndPagePrinter(printer);EndDocPrinter(printer);ClosePrinter(printer);}
  if !ok||written as usize!=bytes.len(){return Err("Printer did not accept the complete receipt. Check paper and connection.".into())}
  Ok(format!("Receipt sent directly to {}",String::from_utf16_lossy(&name).trim_end_matches('\0')))
 }
 #[cfg(not(windows))] {let _=text;Err("Direct printing is supported in the Windows desktop app.".into())}
}
'@
$rust=$rust.Replace('fn main(){',$printer+[Environment]::NewLine+'fn main(){')
}
$rust=$rust.Replace('tauri::generate_handler![storage_info]','tauri::generate_handler![storage_info,print_receipt]');Set-Content -LiteralPath $rustPath -Value $rust -NoNewline -Encoding utf8
Write-Host 'Applied NITRAM fixes.'
