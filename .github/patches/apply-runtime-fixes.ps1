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
 x.onload=()=>{_nitramSaveBusy=false;if(x.status>=200&&x.status<300){try{const r=JSON.parse(x.responseText);_nitramSaveRevision=r.revision||(_nitramSaveRevision+1);/* successful autosave is intentionally silent */}catch(e){/* successful autosave is intentionally silent */}}else{window.NITRAM_STORAGE.setStatus('DATABASE SAVE FAILED — '+(x.responseText||x.statusText),true);_nitramPendingSave=payload}if(_nitramPendingSave)_nitramFlushSave()};
 x.onerror=()=>{_nitramSaveBusy=false;_nitramPendingSave=payload;window.NITRAM_STORAGE.setStatus('DATABASE SAVE FAILED — connection error',true)};x.send(payload);
}
const save=()=>{try{if(_nitramSaveTimer)clearTimeout(_nitramSaveTimer);_nitramSaveTimer=setTimeout(()=>{_nitramPendingSave=JSON.stringify(S);_nitramFlushSave()},35);return true}catch(e){window.NITRAM_STORAGE.setStatus('DATABASE SAVE FAILED — '+String(e.message||e),true);throw e}};
window.addEventListener('beforeunload',()=>{try{if(_nitramSaveTimer)clearTimeout(_nitramSaveTimer);const x=new XMLHttpRequest();x.open('POST',window.NITRAM_STORAGE.endpoint+'/state',false);x.setRequestHeader('Authorization','Bearer '+window.NITRAM_STORAGE.token);x.setRequestHeader('Content-Type','application/json');x.send(JSON.stringify(S))}catch(e){console.error('Final save failed',e)}});
const prod=id=>S.products.find(p=>p.id===id);
'@
$a=$app.IndexOf('let _nitramSaveRevision=0;');$b=$app.IndexOf('// Persist the compacted live catalogue',$a);if($a -lt 0 -or $b -lt 0){throw 'Save patch markers missing'};$app=$app.Substring(0,$a)+$save+$app.Substring($b)
$receipt=@'
function receiptPlainText(s){
 const rows=['[C][B]NITRAM SUPERMARKET','[C]SALES RECEIPT','[L]------------------------------------------','[B]Receipt No: '+(s.receipt||'-'),'Date: '+(s.date||''),'Served by: '+(s.soldBy||'Unknown'),'[L]------------------------------------------','[B]ITEM / QTY                         AMOUNT'];
 (s.items||[]).forEach(x=>{rows.push('[B]'+String(x.name||(prod(x.id)||{}).name||x.id));rows.push('  '+x.qty+' x '+Number(x.price||0).toFixed(2)+'                  '+(Number(x.price||0)*Number(x.qty||0)).toFixed(2))});
 rows.push('[L]------------------------------------------','[B]TOTAL: KES '+Number(s.netTotal??s.total??0).toFixed(2),'Payment: '+(s.payment||'-'),'Received: '+(s.received==null?'Not entered':'KES '+Number(s.received).toFixed(2)),'Change: '+(s.change==null?'-':'KES '+Number(s.change).toFixed(2)),'[L]------------------------------------------','[C][B]'+(S.receiptFooter||'Thank you for shopping with us!'),'[C]Please keep this receipt for your records.','','');return rows.join('\n');
}
async function printReceiptDirect(){const s=window._nitramReceiptToPrint;if(!s)return toast('Receipt data is unavailable');const invoke=window.__TAURI__?.core?.invoke;if(!invoke)return toast('Direct printing is available only in the installed NITRAM app');try{toast('Sending receipt to the default Windows printer…');const r=await invoke('print_receipt',{text:receiptPlainText(s)});closeModal();toast(r||'Receipt sent to printer')}catch(e){console.error(e);toast('Printing failed: '+String(e?.message||e))}}
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


# Replace the old Sales History date controls with a self-contained, tested row-date filter.
$htmlPath=Join-Path $project 'dist/index.html'
$html=Get-Content -LiteralPath $htmlPath -Raw
$begin=$html.IndexOf('<script>' )
if($html.Contains('data-nitram-date-presets')){
  $html=[regex]::Replace($html,'(?s)<script>\s*\(\(\)=>\{.*?data-nitram-date-presets.*?</script>','')
}
$dateFilter=@'
<script id="nitram-sales-date-filter">
(()=>{
 const pad=n=>String(n).padStart(2,'0');
 const day=d=>new Date(d.getFullYear(),d.getMonth(),d.getDate());
 const iso=d=>d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate());
 const parseDate=s=>{
  const m=String(s||'').match(/(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})/);
  if(!m)return null;const d=new Date(+m[3],+m[2]-1,+m[1]);
  return d.getFullYear()===+m[3]&&d.getMonth()===+m[2]-1&&d.getDate()===+m[1]?d:null;
 };
 let active=false,mode='today',from=null,to=null,table=null,body=null,rows=[];
 const findView=()=>{
  const hs=[...document.querySelectorAll('h1,h2,h3')];
  const h=hs.find(x=>(x.textContent||'').trim().toLowerCase()==='sales history');
  if(!h)return null;
  let n=h;
  for(let i=0;i<7&&n;i++,n=n.parentElement){
   const t=n.querySelector('table');
   if(t&&/receipt/i.test(t.innerText)&&/date/i.test(t.innerText))return {h,root:n,table:t};
  }
  return null;
 };
 const dateColumn=t=>{
  const th=[...t.querySelectorAll('thead th')];
  let i=th.findIndex(x=>(x.textContent||'').trim().toLowerCase()==='date');
  if(i>=0)return i;
  const first=t.querySelector('tr');if(!first)return -1;
  return [...first.children].findIndex(x=>(x.textContent||'').trim().toLowerCase()==='date');
 };
 const apply=()=>{
  if(!table||!table.isConnected)return;
  const col=dateColumn(table);if(col<0)return;
  const now=day(new Date());let start=null,end=null;
  if(mode==='today'){start=now;end=new Date(now);end.setDate(end.getDate()+1)}
  if(mode==='yesterday'){end=now;start=new Date(now);start.setDate(start.getDate()-1)}
  if(mode==='week'){start=new Date(now);start.setDate(start.getDate()-6);end=new Date(now);end.setDate(end.getDate()+1)}
  if(mode==='month'){start=new Date(now);start.setMonth(start.getMonth()-1);end=new Date(now);end.setDate(end.getDate()+1)}
  if(mode==='year'){start=new Date(now);start.setFullYear(start.getFullYear()-1);end=new Date(now);end.setDate(end.getDate()+1)}
  if(mode==='custom'){
   if(!from||!to){rows.forEach(r=>r.style.display='');return}
   start=new Date(from+'T00:00:00');end=new Date(to+'T00:00:00');end.setDate(end.getDate()+1);
  }
  rows=[...table.querySelectorAll('tbody tr')];
  rows.forEach(r=>{
   const cell=r.children[col],d=parseDate(cell?.textContent||'');
   r.style.display=(!d||!start||!end)?'':(d>=start&&d<end?'':'none');
  });
 };
 const install=()=>{
  const v=findView();if(!v)return;
  table=v.table;
  const oldDates=[...v.root.querySelectorAll('input[type="date"]')];
  oldDates.forEach(el=>{let p=el;for(let i=0;i<3&&p.parentElement&&p.parentElement!==v.root;i++)p=p.parentElement;p.style.display='none';});
  let bar=v.root.querySelector('[data-nitram-date-presets]');
  if(!bar){
   bar=document.createElement('div');bar.dataset.nitramDatePresets='1';
   bar.style.cssText='display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:8px 0 14px';
   const title=document.createElement('strong');title.textContent='Date range';title.style.cssText='font-size:13px;color:#344054';
   const select=document.createElement('select');select.setAttribute('aria-label','Sales History date range');
   select.style.cssText='padding:9px 12px;border:1px solid #d0d5dd;border-radius:9px;background:#fff;color:#344054;font:inherit';
   [['today','Today'],['yesterday','Yesterday'],['week','1 week'],['month','1 month'],['year','1 year'],['custom','Custom date']].forEach(([value,label])=>{const o=document.createElement('option');o.value=value;o.textContent=label;select.appendChild(o)});
   const start=document.createElement('input');start.type='date';start.setAttribute('aria-label','Custom start date');start.style.cssText='display:none;padding:8px;border:1px solid #d0d5dd;border-radius:8px';
   const end=document.createElement('input');end.type='date';end.setAttribute('aria-label','Custom end date');end.style.cssText='display:none;padding:8px;border:1px solid #d0d5dd;border-radius:8px';
   select.addEventListener('change',()=>{mode=select.value;const custom=mode==='custom';start.style.display=end.style.display=custom?'':'none';if(!custom)apply();else apply()});
   start.addEventListener('change',()=>{from=start.value;mode='custom';apply()});
   end.addEventListener('change',()=>{to=end.value;mode='custom';apply()});
   bar.append(title,select,start,end);
   const filters=[...v.root.querySelectorAll('input')].find(x=>x.type==='text'||x.type==='search');
   const anchor=filters?.parentElement||oldDates[0]?.parentElement?.parentElement||v.table;
   anchor.parentElement.insertBefore(bar,anchor);
  }
  apply();
 };
 const observer=new MutationObserver(()=>{const v=findView();if(v&&v.table!==table){table=v.table;install()}else if(v)install()});
 const start=()=>{install();observer.observe(document.body,{childList:true,subtree:true});};
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
</script>
'@
if(-not $html.Contains('id="nitram-sales-date-filter"')){$html=$html.Replace('</body>',$dateFilter+[Environment]::NewLine+'</body>')}
Set-Content -LiteralPath $htmlPath -Value $html -NoNewline -Encoding utf8


# Import the new 4,728-row ROBIPOS catalogue from the checked-in CSV segments.
$catalogueDir=Join-Path $env:GITHUB_WORKSPACE 'catalogue-import'
$parts=1..5 | ForEach-Object { Join-Path $catalogueDir ("productlist20-part"+$_+".csv") }
if(@($parts | Where-Object { Test-Path -LiteralPath $_ }).Count -ne 5){throw 'The five productlist20.csv source segments are required.'}
$combined=Join-Path $env:RUNNER_TEMP 'productlist20-combined.csv'
$writer=[System.IO.StreamWriter]::new($combined,$false,[System.Text.UTF8Encoding]::new($false))
try{foreach($part in $parts){$writer.Write([System.IO.File]::ReadAllText($part))}}finally{$writer.Dispose()}
$headers=@('sourceProductId','name','categoryId','supplierId','field05','taxIncluded','buy','price','promoPrice','wholesalePrice','field11','field12','field13','field14','field15','sourceBarcodeUid','field17','field18','field19','stock','updatedAt','updatedBy','field23','field24','expiryDate','itemType','priceMode','brand','status','field30','barcode','unit','productType','vatType','field35','field36','field37','field38','field39','field40','field41','field42','field43','field44')
$sourceRows=@(Import-Csv -LiteralPath $combined -Header $headers)
if($sourceRows.Count -ne 4728){throw "Catalogue row-count check failed: expected 4728, found $($sourceRows.Count)."}
function Convert-NitramNumber($value){$n=0.0;$s=([string]$value).Trim();if([double]::TryParse($s,[Globalization.NumberStyles]::Any,[Globalization.CultureInfo]::InvariantCulture,[ref]$n)){return $n};return 0.0}
$products=foreach($r in $sourceRows){
 $raw=@($headers | ForEach-Object { [string]$r.$_ })
 $barcode=([string]$r.barcode).Trim()
 if([string]::IsNullOrWhiteSpace($barcode)){throw "Catalogue product $($r.sourceProductId) has no barcode."}
 $warnings=@()
 if(([string]$r.buy).Trim() -notmatch '^-?\d+(\.\d+)?$'){$warnings+=("Buying price source value: "+$r.buy)}
 if(([string]$r.price).Trim() -notmatch '^-?\d+(\.\d+)?$'){$warnings+=("Selling price source value: "+$r.price)}
 $stock=Convert-NitramNumber $r.stock
 if($stock -lt 0 -or $stock -gt 100000){$warnings+=("Unusual source stock quantity: "+$r.stock)}
 [pscustomobject]@{
  id=$barcode;barcode=$barcode;name=([string]$r.name).Trim();cat=("Category "+([string]$r.categoryId).Trim())
  buy=(Convert-NitramNumber $r.buy);price=(Convert-NitramNumber $r.price);stock=$stock
  reorder=0;promoPrice=(Convert-NitramNumber $r.promoPrice);wholesalePrice=(Convert-NitramNumber $r.wholesalePrice)
  sourceProductId=[string]$r.sourceProductId;sourceQuantity=[string]$r.stock;supplierId=[string]$r.supplierId
  taxIncluded=[string]$r.taxIncluded;sourceBarcodeUid=[string]$r.sourceBarcodeUid;updatedAt=[string]$r.updatedAt
  brand=[string]$r.brand;unit=[string]$r.unit;productType=[string]$r.productType;vatType=[string]$r.vatType;status=[string]$r.status
  sourceColumns=$raw;importWarnings=$warnings
 }
}
if(@($products | Select-Object -ExpandProperty barcode -Unique).Count -ne 4728){throw 'Catalogue barcode uniqueness check failed.'}
$productJson=ConvertTo-Json -InputObject @($products) -Depth 8 -Compress
$pattern='(?s)const ROBIPOS_PRODUCTS=\[.*?\];\s*const seed='
$replacement='const ROBIPOS_PRODUCTS='+$productJson+';'+[Environment]::NewLine+'const seed='
$app=[regex]::Replace($app,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m)$replacement},1)
if($app -notmatch 'const ROBIPOS_PRODUCTS=\['){throw 'Could not replace the original product catalogue in app.js.'}
# Replace the one-time old-catalogue migration without touching sales, shifts, users or financial records.
$app=[regex]::Replace($app,'(?s)if\(S\.productlist74ImportVersion!==1\)\s*\{\s*S\.products=JSON\.parse\(JSON\.stringify\(ROBIPOS_PRODUCTS\)\);\s*S\.productlist74ImportVersion=1;\s*S\.productlist74ImportedAt=.*?;\s*\}',"if(S.productlist20ImportVersion!==1){S.products=JSON.parse(JSON.stringify(ROBIPOS_PRODUCTS));S.productlist20ImportVersion=1;S.productlist20ImportedAt='2026-11-07';}",1)
if($app -notmatch 'productlist20ImportVersion'){throw 'Could not install the one-time productlist20 catalogue migration.'}
# Keep held-sale snapshots intact when their old catalogue entries are replaced.
$app=$app.Replace("S.held=S.held.filter(h=>h&&Array.isArray(h.items)).map(h=>({...h,items:h.items.filter(x=>x&&S.products.some(p=>p.id===String(x.id))).map(x=>({...x,id:String(x.id),qty:Math.max(1,Math.floor(Number(x.qty)||1))}))})).filter(h=>h.items.length);","S.held=S.held.filter(h=>h&&Array.isArray(h.items)).map(h=>({...h,items:h.items.filter(Boolean).map(x=>({...x,id:String(x.id),qty:Math.max(1,Math.floor(Number(x.qty)||1))}))}));")
# Add portable backup controls to the Products and Sales History screens.
$app=$app.Replace('<button class=btn onclick="productForm()">+ Add Product</button></div>','<div style="display:flex;gap:7px;flex-wrap:wrap"><button class=ghost onclick="exportProductsBackup(''csv'')">Export CSV</button><button class=ghost onclick="exportProductsBackup(''json'')">Export JSON</button><button class=ghost onclick="chooseBackupImport(''products'')">Import Backup</button><button class=btn onclick="productForm()">+ Add Product</button></div></div>')
$app=$app.Replace('<button class=ghost onclick="printLast()">🖨 Print latest receipt</button></div>','<div style="display:flex;gap:7px;flex-wrap:wrap"><button class=ghost onclick="exportSalesBackup(''csv'')">Export CSV</button><button class=ghost onclick="exportSalesBackup(''json'')">Export JSON</button><button class=ghost onclick="chooseBackupImport(''sales'')">Import Backup</button><button class=ghost onclick="printLast()">🖨 Print latest receipt</button></div></div>')
$backupJs=@'
function _nitramDownload(text,filename,type){const blob=new Blob([text],{type}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1500)}
function _nitramCsv(rows){return rows.map(r=>r.map(v=>'"'+String(v??'').replace(/"/g,'""')+'"').join(',')).join('\r\n')}
function exportProductsBackup(format){const p=(S.products||[]).map(x=>({...x})),date=new Date().toISOString().slice(0,10);if(format==='json')_nitramDownload(JSON.stringify({format:'NITRAM_PRODUCTS',version:1,exportedAt:new Date().toISOString(),products:p},null,2),'NITRAM_Products_'+date+'.json','application/json');else{const keys=['barcode','name','category','buying_price','selling_price','stock','reorder_level','unit','vat_type','status'];const rows=[keys,...p.map(x=>[x.barcode||x.id,x.name,x.cat,x.buy,x.price,x.stock,x.reorder,x.unit,x.vatType,x.status])];_nitramDownload('\ufeff'+_nitramCsv(rows),'NITRAM_Products_'+date+'.csv','text/csv;charset=utf-8')}}
function exportSalesBackup(format){const sales=(S.sales||[]).map(x=>({...x})),date=new Date().toISOString().slice(0,10);if(format==='json')_nitramDownload(JSON.stringify({format:'NITRAM_SALES',version:1,exportedAt:new Date().toISOString(),sales},null,2),'NITRAM_Sales_History_'+date+'.json','application/json');else{const keys=['receipt','date','sold_by','payment','total','net_total','status','items_json'];const rows=[keys,...sales.map(x=>[x.receipt,x.date,x.soldBy,x.payment,x.total,x.netTotal,saleStatus(x),JSON.stringify(x.items||[])])];_nitramDownload('\ufeff'+_nitramCsv(rows),'NITRAM_Sales_History_'+date+'.csv','text/csv;charset=utf-8')}}
function chooseBackupImport(kind){const input=document.createElement('input');input.type='file';input.accept='.json,.csv,.tsv,.txt,.xml,application/json,text/csv,text/tab-separated-values,text/plain,application/xml';input.onchange=e=>importPortableBackup(e,kind);input.click()}
function _nitramParseDelimited(text,delimiter){const rows=[];let row=[],field='',quoted=false;for(let i=0;i<text.length;i++){const c=text[i];if(quoted){if(c==='"'&&text[i+1]==='"'){field+='"';i++}else if(c==='"')quoted=false;else field+=c}else if(c==='"')quoted=true;else if(c===delimiter){row.push(field);field=''}else if(c==='\n'){row.push(field.replace(/\r$/,''));if(row.some(x=>x!==''))rows.push(row);row=[];field=''}else field+=c}if(field||row.length){row.push(field.replace(/\r$/,''));rows.push(row)}return rows}
function _nitramNormalizeProduct(x){const get=(...names)=>{for(const n of names){const k=Object.keys(x||{}).find(z=>z.toLowerCase().replace(/[^a-z0-9]/g,'')===n);if(k&&x[k]!==''&&x[k]!=null)return x[k]}return ''};const barcode=String(get('barcode','ean','sku','productcode','id','itemcode')).trim(),name=String(get('name','product','productname','description','item')).trim();if(!barcode||!name)return null;const n=v=>{const z=Number(String(v??'').replace(/,/g,''));return Number.isFinite(z)?z:0};return{id:barcode,barcode,name,cat:String(get('category','cat','categoryname')||'Uncategorised'),buy:n(get('buy','buyingprice','cost','costprice','purchaseprice')),price:n(get('price','sellingprice','retailprice','unitprice')),stock:n(get('stock','quantity','qty','onhand','available')),reorder:n(get('reorder','reorderlevel','minimumstock')),unit:String(get('unit','uom')||'pcs'),vatType:String(get('vattype','taxstatus')||''),status:String(get('status')||'active')}}
function importPortableBackup(event,kind){const file=event.target.files?.[0];if(!file)return;const reader=new FileReader();reader.onload=()=>{try{const text=String(reader.result||'').replace(/^\ufeff/,'').trim();let data,rows;if(file.name.toLowerCase().endsWith('.json')||/^[\[{]/.test(text)){data=JSON.parse(text)}else if(file.name.toLowerCase().endsWith('.xml')||text.startsWith('<?xml')){const doc=new DOMParser().parseFromString(text,'application/xml');if(doc.querySelector('parsererror'))throw Error('XML file could not be read');data=[...doc.querySelectorAll('row,product,sale,item')].map(el=>Object.fromEntries([...el.children].map(n=>[n.tagName,n.textContent])))}else{const delimiter=(text.split(/\r?\n/,1)[0].split('\t').length>text.split(/\r?\n/,1)[0].split(',').length)?'\t':',';rows=_nitramParseDelimited(text,delimiter);const heads=(rows.shift()||[]).map(x=>x.trim());data=rows.map(row=>Object.fromEntries(heads.map((h,i)=>[h,row[i]??''])))}if(kind==='products'){let list=Array.isArray(data)?data:(data.products||data.items||data.data||data.Products);if(!Array.isArray(list))throw Error('No product records were found in this file');const clean=list.map(_nitramNormalizeProduct).filter(Boolean);if(!clean.length)throw Error('No rows contained a recognizable barcode and product name');const unique=new Map();clean.forEach(p=>unique.set(p.barcode,p));if(!confirm('Replace the current product catalogue with '+unique.size+' imported products? Sales history and other POS records will be retained. Export your current Products backup first if needed.'))return;S.products=[...unique.values()];S.productlist20ImportVersion=2;S.cart=(S.cart||[]).filter(x=>S.products.some(p=>p.id===String(x.id)));save();render('products');toast('Imported '+S.products.length+' products. '+(clean.length-unique.size)+' duplicate barcode rows were merged.')}else{let list=Array.isArray(data)?data:(data.sales||data.transactions||data.items||data.data||data.Sales);if(!Array.isArray(list))throw Error('No sales records were found in this file');const existing=new Set((S.sales||[]).map(x=>String(x.receipt||x.id||'')));let added=0;list.forEach(x=>{const receipt=String(x.receipt||x.receipt_no||x.receiptNumber||x.invoice||x.id||'').trim();if(!receipt||existing.has(receipt))return;const total=Number(x.total??x.amount??x.net_total??0);S.sales.push({...x,id:x.id||'IMPORT-'+receipt,receipt,date:x.date||x.timestamp||'',soldBy:x.soldBy||x.sold_by||x.cashier||'Imported',payment:x.payment||x.payment_method||'Unknown',total:Number.isFinite(total)?total:0,items:Array.isArray(x.items)?x.items:(()=>{try{return JSON.parse(x.items_json||x.itemsJson||'[]')}catch{return []}})()});existing.add(receipt);added++});if(!added)throw Error('No new sales were imported. Existing receipt numbers may already be present or the file may lack receipt numbers.');save();render('sales');toast('Imported '+added+' new sales records; duplicates were skipped.')}}catch(err){console.error(err);toast('Could not import this file: '+String(err.message||err))}finally{event.target.value=''}};reader.readAsText(file)}
'@
$marker='function downloadCSV(rows,filename)'
if(-not $app.Contains($marker)){throw 'Could not locate CSV utility insertion point.'}
$app=$app.Replace($marker,$backupJs+[Environment]::NewLine+$marker)
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8



# Targeted repairs requested: Sales History search/paging/backups, Products backups,
# Held Sales search responsiveness, and combined Cash + M-Pesa shift variance.
$app = Get-Content -LiteralPath $appPath -Raw

$oldSalesPrefix = 'function sales(){const all=S.sales.slice().sort((a,b)=>new Date(b.id)-new Date(a.id));return'
if (-not $app.Contains($oldSalesPrefix)) { throw 'Sales History renderer marker changed; refusing to patch an unexpected source.' }
$app = $app.Replace($oldSalesPrefix,'let salesPage=0,salesPageSize=50,salesFiltered=[];' + [Environment]::NewLine + 'function sales(){const all=S.sales.slice().sort((a,b)=>Number(b.id)-Number(a.id));salesFiltered=all;salesPage=0;return')
$app = $app.Replace('<input id="salesSearch" placeholder="Search receipt, cashier, payment or product..." oninput="filterSales()" style="flex:1;min-width:220px;max-width:440px;padding:10px;border:1px solid #d0d5dd;border-radius:9px">','<input id="salesSearch" class=field placeholder="Search receipt, cashier, payment or product..." oninput="filterSales()" style="flex:1;min-width:220px;max-width:440px;width:100%" autocomplete=off>')
$app = $app.Replace('<input id="salesFrom" type="date" aria-label="From date" onchange="filterSales()" style="padding:9px;border:1px solid #d0d5dd;border-radius:9px">','<select id="salesRange" class=field aria-label="Sales date range" onchange="applySalesRange()" style="min-width:130px"><option value=all>All dates</option><option value=today>Today</option><option value=yesterday>Yesterday</option><option value=week>1 week</option><option value=month>1 month</option><option value=year>1 year</option><option value=custom>Custom date</option></select><input id="salesFrom" type="date" aria-label="From date" onchange="filterSales()" style="display:none;padding:9px;border:1px solid #d0d5dd;border-radius:9px">')
$app = $app.Replace('<input id="salesTo" type="date" aria-label="To date" onchange="filterSales()" style="padding:9px;border:1px solid #d0d5dd;border-radius:9px">','<input id="salesTo" type="date" aria-label="To date" onchange="filterSales()" style="display:none;padding:9px;border:1px solid #d0d5dd;border-radius:9px">')

$oldSalesActions = @'
<div style="display:flex;gap:7px;flex-wrap:wrap"><button class=ghost onclick="exportSalesBackup(''csv'')">Export CSV</button><button class=ghost onclick="exportSalesBackup(''json'')">Export JSON</button><button class=ghost onclick="chooseBackupImport(''sales'')">Import Backup</button><button class=ghost onclick="printLast()">🖨 Print latest receipt</button></div>
'@
$newSalesActions = @'
<div style="display:flex;gap:7px;flex-wrap:wrap;align-items:center"><select id=salesExportFormat class=field aria-label="Sales export format" style="width:auto;min-width:95px"><option value=csv>CSV</option><option value=json>JSON</option></select><button class=ghost onclick="exportSalesBackup(document.getElementById('salesExportFormat').value)">Export</button><button class=ghost onclick="chooseBackupImport('sales')">Import Backup</button><button class=ghost onclick="printLast()">🖨 Print latest receipt</button></div>
'@
$app = $app.Replace($oldSalesActions.Trim(),$newSalesActions.Trim())
if ($app.Contains('<button class=ghost onclick="printLast()">🖨 Print latest receipt</button></div>')) {
 $app = $app.Replace('<button class=ghost onclick="printLast()">🖨 Print latest receipt</button></div>',$newSalesActions.Trim())
}

$salesStart = $app.IndexOf('function sales(){')
$salesEnd = $app.IndexOf('function salesRow(', $salesStart)
if ($salesStart -lt 0 -or $salesEnd -lt 0) { throw 'Sales History function boundaries were not found.' }
$salesBlock = $app.Substring($salesStart,$salesEnd-$salesStart)
$salesBlock = [regex]::Replace($salesBlock,'all\.map\(s=>salesRow\(s\)\)\.join\(''\)','all.slice(0,salesPageSize).map(s=>salesRow(s)).join('''')',1)
$salesBlock = $salesBlock.Replace('</tbody></table></div></div>','</tbody></table></div><div id=salesPager style="display:flex;align-items:center;justify-content:space-between;gap:10px;padding:12px;flex-wrap:wrap"><span id=salesPageInfo class=muted>Sales pages</span><div style="display:flex;gap:8px"><button class=ghost id=salesPrev onclick="changeSalesPage(-1)">Previous</button><button class=ghost id=salesNext onclick="changeSalesPage(1)">Next</button></div></div></div>')
$app = $app.Substring(0,$salesStart) + $salesBlock + $app.Substring($salesEnd)

$newSalesFunctions = @'
function applySalesRange(){
 const mode=document.getElementById('salesRange')?.value||'all',fromEl=document.getElementById('salesFrom'),toEl=document.getElementById('salesTo');
 if(!fromEl||!toEl)return;
 const custom=mode==='custom';fromEl.style.display=toEl.style.display=custom?'':'none';
 if(custom){filterSales();return}
 const pad=n=>String(n).padStart(2,'0'),key=d=>d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate());
 const today=new Date();today.setHours(0,0,0,0);let from=null,to=null;
 if(mode==='today'){from=today;to=today}
 else if(mode==='yesterday'){from=new Date(today);from.setDate(from.getDate()-1);to=from}
 else if(mode==='week'){from=new Date(today);from.setDate(from.getDate()-6);to=today}
 else if(mode==='month'){from=new Date(today);from.setMonth(from.getMonth()-1);to=today}
 else if(mode==='year'){from=new Date(today);from.setFullYear(from.getFullYear()-1);to=today}
 fromEl.value=from?key(from):'';toEl.value=to?key(to):'';filterSales();
}
function filterSales(){
 const q=(document.getElementById('salesSearch')?.value||'').trim().toLowerCase(),from=document.getElementById('salesFrom')?.value||'',to=document.getElementById('salesTo')?.value||'',statusFilter=document.getElementById('salesStatus')?.value||'';
 salesFiltered=(S.sales||[]).slice().sort((a,b)=>Number(b.id)-Number(a.id)).filter(s=>{
  const status=saleStatus(s),dateObj=new Date(s.date),dateKey=!isNaN(dateObj)?dateObj.getFullYear()+'-'+String(dateObj.getMonth()+1).padStart(2,'0')+'-'+String(dateObj.getDate()).padStart(2,'0'):'';
  const text=[s.receipt,s.date,s.soldBy,s.payment,...(s.items||[]).map(x=>x.name||(prod(x.id)||{}).name||x.id)].join(' ').toLowerCase();
  return text.includes(q)&&(!from||dateKey>=from)&&(!to||dateKey<=to)&&(!statusFilter||status===statusFilter);
 });
 salesPage=0;drawSalesPage();
}
function drawSalesPage(){
 const body=document.getElementById('salesRows');if(!body)return;
 const total=salesFiltered.length,pages=Math.max(1,Math.ceil(total/salesPageSize));salesPage=Math.max(0,Math.min(salesPage,pages-1));
 const start=salesPage*salesPageSize;body.innerHTML=total?salesFiltered.slice(start,start+salesPageSize).map(s=>salesRow(s)).join(''):'<tr><td colspan=8 style="text-align:center;padding:35px">No matching sales.</td></tr>';
 const info=document.getElementById('salesPageInfo');if(info)info.textContent=total?'Showing '+(start+1)+'–'+Math.min(start+salesPageSize,total)+' of '+total:'Showing 0 of 0';
 const prev=document.getElementById('salesPrev'),next=document.getElementById('salesNext');if(prev)prev.disabled=salesPage===0;if(next)next.disabled=salesPage>=pages-1;
}
function changeSalesPage(delta){salesPage+=delta;drawSalesPage()}
'@
$app = [regex]::Replace($app,'(?s)function filterSales\(\)\{.*?(?=function saleStatus\()', [System.Text.RegularExpressions.MatchEvaluator]{param($m)$newSalesFunctions+[Environment]::NewLine},1)
if (-not $app.Contains('function drawSalesPage()')) { throw 'Sales History pagination patch did not apply.' }

$oldProductsActions = @'
<div style="display:flex;gap:7px;flex-wrap:wrap"><button class=ghost onclick="exportProductsBackup(''csv'')">Export CSV</button><button class=ghost onclick="exportProductsBackup(''json'')">Export JSON</button><button class=ghost onclick="chooseBackupImport(''products'')">Import Backup</button><button class=btn onclick="productForm()">+ Add Product</button></div>
'@
$newProductsActions = @'
<div style="display:flex;gap:7px;flex-wrap:wrap;align-items:center"><select id=productsExportFormat class=field aria-label="Products export format" style="width:auto;min-width:95px"><option value=csv>CSV</option><option value=json>JSON</option></select><button class=ghost onclick="exportProductsBackup(document.getElementById('productsExportFormat').value)">Export</button><button class=ghost onclick="chooseBackupImport('products')">Import Backup</button><button class=btn onclick="productForm()">+ Add Product</button></div>
'@
$app = $app.Replace($oldProductsActions.Trim(),$newProductsActions.Trim())
if ($app.Contains('<button class=btn onclick="productForm()">+ Add Product</button></div>')) {
 $app = $app.Replace('<button class=btn onclick="productForm()">+ Add Product</button></div>',$newProductsActions.Trim())
}
$app = $app.Replace('function exportProductsBackup(format){const p=',"function exportProductsBackup(format){format=format||document.getElementById('productsExportFormat')?.value||'csv';const p=")
$app = $app.Replace('function exportSalesBackup(format){const sales=',"function exportSalesBackup(format){format=format||document.getElementById('salesExportFormat')?.value||'csv';const sales=")

# Held Sales: debounce the existing search so typing does not rebuild the full page on every keystroke.
$oldHeldHandler = 'oninput="window.heldCustomerQuery=this.value;const v=this.value;render(''held'');const el=document.getElementById(''heldCustomerSearch'');if(el){el.focus();el.setSelectionRange(v.length,v.length)}"'
$newHeldHandler = 'oninput="searchHeldSales(this.value)"'
if ($app.Contains($oldHeldHandler)) { $app = $app.Replace($oldHeldHandler,$newHeldHandler) }
$heldSearchFunction = @'
let heldSearchTimer=0;
function searchHeldSales(value){
 window.heldCustomerQuery=String(value||'');const position=window.heldCustomerQuery.length;
 if(heldSearchTimer)clearTimeout(heldSearchTimer);
 heldSearchTimer=setTimeout(()=>{render('held');const input=document.getElementById('heldCustomerSearch');if(input){input.focus({preventScroll:true});input.setSelectionRange(position,position)}},100);
}
'@
$app = $app.Replace('function confirmResumePayLaterGroup', $heldSearchFunction + [Environment]::NewLine + 'function confirmResumePayLaterGroup')
if (-not $app.Contains('function searchHeldSales(value)')) { throw 'Held Sales search patch did not apply.' }

# Main shift variance now combines physical cash and confirmed M-Pesa against all net sales.
# Existing fields, labels and layout remain unchanged.
$app = $app.Replace(
 'expected=Number(sh.openingFloat||0)+cashSales-cashOut,variance=counted+expenses-expected,mpesaVariance=mpesaCounted-mpesaSales',
 'expected=Number(sh.openingFloat||0)+cashSales-cashOut,variance=counted+expenses+cashOut+mpesaCounted-Number(sh.openingFloat||0)-netSales,mpesaVariance=mpesaCounted-mpesaSales'
)
$app = $app.Replace(
 'cashSales=sales.filter(x=>x.payment===''Cash'').reduce((n,x)=>n+net(x),0),mpesaSales=sales.filter(x=>x.payment===''M-Pesa'').reduce((n,x)=>n+net(x),0),cashOut=(S.cashOutflows||[]).filter(x=>x.payment===''Cash''&&x.shiftId===sh.id).reduce((n,x)=>n+Number(x.amount||0),0),expected=Number(sh.openingFloat||0)+cashSales-cashOut;const el=document.getElementById(''shiftVarianceDisplay'');if(el)el.value=money(counted+expense-expected);',
 'totalSales=sales.reduce((n,x)=>n+net(x),0),cashOut=(S.cashOutflows||[]).filter(x=>x.payment===''Cash''&&x.shiftId===sh.id).reduce((n,x)=>n+Number(x.amount||0),0);const el=document.getElementById(''shiftVarianceDisplay'');if(el)el.value=money(counted+expense+cashOut+mpesaCounted-Number(sh.openingFloat||0)-totalSales);'
)
if (-not $app.Contains('variance=counted+expenses+cashOut+mpesaCounted-Number(sh.openingFloat||0)-netSales')) {
 throw 'Combined shift variance formula did not apply.'
}
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8

$htmlPath = Join-Path $project 'dist/index.html'
$html = Get-Content -LiteralPath $htmlPath -Raw
$html = [regex]::Replace($html,'(?s)<script id="nitram-sales-date-filter">.*?</script>','')
Set-Content -LiteralPath $htmlPath -Value $html -NoNewline -Encoding utf8

node --check $appPath
Write-Host 'Applied only the six requested NITRAM repairs.'



# Final exact-match guards for the requested single-button exports and Sales History paging.
$app = Get-Content -LiteralPath $appPath -Raw
$quote = [char]39
$oldRows = 'all.map(s=>salesRow(s)).join(' + $quote + $quote + ')'
$newRows = 'all.slice(0,salesPageSize).map(s=>salesRow(s)).join(' + $quote + $quote + ')'
$salesStart = $app.IndexOf('function sales(){')
$salesEnd = $app.IndexOf('function salesRow(', $salesStart)
if ($salesStart -lt 0 -or $salesEnd -lt 0) { throw 'Sales History pagination validation could not locate its renderer.' }
$salesBlock = $app.Substring($salesStart,$salesEnd-$salesStart)
$salesBlock = $salesBlock.Replace($oldRows,$newRows)
if (-not $salesBlock.Contains('all.slice(0,salesPageSize).map(s=>salesRow(s))')) { throw 'Sales History is not limited to one page of 50 records.' }
if (-not $salesBlock.Contains('id=salesPager')) { throw 'Sales History page controls were not inserted.' }
$app = $app.Substring(0,$salesStart) + $salesBlock + $app.Substring($salesEnd)

$singleSales = @'
<div style="display:flex;gap:7px;flex-wrap:wrap;align-items:center"><select id=salesExportFormat class=field aria-label="Sales export format" style="width:auto;min-width:95px"><option value=csv>CSV</option><option value=json>JSON</option></select><button class=ghost onclick="exportSalesBackup(document.getElementById('salesExportFormat').value)">Export</button><button class=ghost onclick="chooseBackupImport('sales')">Import Backup</button><button class=ghost onclick="printLast()">🖨 Print latest receipt</button></div>
'@
$salesActionPattern = '<div style="display:flex;gap:7px;flex-wrap:wrap"><button class=ghost onclick="exportSalesBackup\(''csv''\)">Export CSV</button>.*?<button class=ghost onclick="printLast\(\)">🖨 Print latest receipt</button></div>'
$app = [regex]::Replace($app,$salesActionPattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m)$singleSales.Trim()},1)
if ($app.Contains('exportSalesBackup(' + $quote + 'csv' + $quote + ')') -or $app.Contains('exportSalesBackup(' + $quote + 'json' + $quote + ')')) { throw 'Sales History still contains multiple export buttons.' }
if (-not $app.Contains('id=salesExportFormat')) { throw 'Sales History export format dropdown was not inserted.' }

$singleProducts = @'
<div style="display:flex;gap:7px;flex-wrap:wrap;align-items:center"><select id=productsExportFormat class=field aria-label="Products export format" style="width:auto;min-width:95px"><option value=csv>CSV</option><option value=json>JSON</option></select><button class=ghost onclick="exportProductsBackup(document.getElementById('productsExportFormat').value)">Export</button><button class=ghost onclick="chooseBackupImport('products')">Import Backup</button><button class=btn onclick="productForm()">+ Add Product</button></div>
'@
$productsActionPattern = '<div style="display:flex;gap:7px;flex-wrap:wrap"><button class=ghost onclick="exportProductsBackup\(''csv''\)">Export CSV</button>.*?<button class=btn onclick="productForm\(\)">\+ Add Product</button></div>'
$app = [regex]::Replace($app,$productsActionPattern,[System.Text.RegularExpressions.MatchEvaluator]{param($m)$singleProducts.Trim()},1)
if ($app.Contains('exportProductsBackup(' + $quote + 'csv' + $quote + ')') -or $app.Contains('exportProductsBackup(' + $quote + 'json' + $quote + ')')) { throw 'Products still contains multiple export buttons.' }
if (-not $app.Contains('id=productsExportFormat')) { throw 'Products export format dropdown was not inserted.' }

Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
node --check $appPath



# Keep the separate M-Pesa variance detail field working while the main variance uses combined takings.
$app = Get-Content -LiteralPath $appPath -Raw
$combinedPreview = @'
function updateShiftExpenseBalance(){
 const counted=Number(document.getElementById('shiftCounted')?.value||0),expense=Number(document.getElementById('shiftExpenseDisplay')?.value||0),mpesaCounted=Number(document.getElementById('shiftMpesaCounted')?.value||0),sh=S.shift||{},sales=(S.sales||[]).filter(x=>sh.id?x.shiftId===sh.id:(!x.shiftId&&new Date(Number(x.timestamp)||new Date(x.date).getTime())>=new Date(sh.openedAt||0))),net=s=>Math.max(0,Number(s.total||0)-Number(s.returnedValue||0)),cashSales=sales.filter(x=>x.payment==='Cash').reduce((n,x)=>n+net(x),0),mpesaSales=sales.filter(x=>x.payment==='M-Pesa').reduce((n,x)=>n+net(x),0),totalSales=sales.reduce((n,x)=>n+net(x),0),cashOut=(S.cashOutflows||[]).filter(x=>x.payment==='Cash'&&x.shiftId===sh.id).reduce((n,x)=>n+Number(x.amount||0),0),expected=Number(sh.openingFloat||0)+cashSales-cashOut;
 const el=document.getElementById('shiftVarianceDisplay');if(el)el.value=money(counted+expense+cashOut+mpesaCounted-Number(sh.openingFloat||0)-totalSales);
 const me=document.getElementById('shiftMpesaVarianceDisplay');if(me)me.value=money(mpesaCounted-mpesaSales);
}
'@
$app = [regex]::Replace($app,'(?s)function updateShiftExpenseBalance\(\)\{.*?(?=function closeCashierShift\()', [System.Text.RegularExpressions.MatchEvaluator]{param($m)$combinedPreview+[Environment]::NewLine},1)
if (-not $app.Contains('totalSales=sales.reduce((n,x)=>n+net(x),0)') -or -not $app.Contains('money(mpesaCounted-mpesaSales)')) { throw 'Shift live variance preview validation failed.' }
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
node --check $appPath
