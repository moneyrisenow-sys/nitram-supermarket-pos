$ErrorActionPreference = 'Stop'
$project = Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT'
$dist = Join-Path $project 'dist'
$xlsxPath = Join-Path $dist 'xlsx.full.min.js'
Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js' -OutFile $xlsxPath
if (-not (Test-Path $xlsxPath) -or (Get-Item $xlsxPath).Length -lt 100000) { throw 'SheetJS offline bundle download failed.' }

$htmlPath = Join-Path $dist 'index.html'
$html = Get-Content -LiteralPath $htmlPath -Raw
$oldLoader = "const script=document.createElement('script');script.src='./app.js';script.onerror=()=>{document.body.innerHTML='<h2>POS interface failed to load</h2>';};document.body.appendChild(script);"
$newLoader = "const loadPos=()=>{const script=document.createElement('script');script.src='./app.js';script.onerror=()=>{document.body.innerHTML='<h2>POS interface failed to load</h2>';};document.body.appendChild(script);};const xlsxScript=document.createElement('script');xlsxScript.src='./xlsx.full.min.js';xlsxScript.onload=loadPos;xlsxScript.onerror=()=>{document.body.innerHTML='<h2>Offline spreadsheet support failed to load</h2>';};document.body.appendChild(xlsxScript);"
if (-not $html.Contains($oldLoader)) { throw 'Could not locate the POS script loader for offline spreadsheet support.' }
$html = $html.Replace($oldLoader,$newLoader)
Set-Content -LiteralPath $htmlPath -Value $html -NoNewline -Encoding utf8

$appPath = Join-Path $dist 'app.js'
$app = Get-Content -LiteralPath $appPath -Raw

$productsFn = @'
function exportProductsBackup(format){
 format=format||document.getElementById('productsExportFormat')?.value||'csv';
 const products=(S.products||[]).map(x=>({...x})),date=new Date().toISOString().slice(0,10),rows=products.map(x=>({barcode:x.barcode||x.id,name:x.name,category:x.cat,buying_price:x.buy,selling_price:x.price,stock:x.stock,reorder_level:x.reorder,unit:x.unit,vat_type:x.vatType,status:x.status}));
 if(format==='json')_nitramDownload(JSON.stringify({format:'NITRAM_PRODUCTS',version:1,exportedAt:new Date().toISOString(),products},null,2),'NITRAM_Products_'+date+'.json','application/json');
 else if(format==='xlsx'){const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(rows),'Products');XLSX.writeFile(wb,'NITRAM_Products_'+date+'.xlsx')}
 else{const keys=['barcode','name','category','buying_price','selling_price','stock','reorder_level','unit','vat_type','status'];const values=[keys,...rows.map(x=>keys.map(k=>x[k]??''))];_nitramDownload('\ufeff'+_nitramCsv(values),'NITRAM_Products_'+date+'.csv','text/csv;charset=utf-8')}
}
'@
$salesFn = @'
function exportSalesBackup(format){
 format=format||document.getElementById('salesExportFormat')?.value||'csv';
 const sales=(S.sales||[]).map(x=>({...x})),date=new Date().toISOString().slice(0,10),rows=sales.map(x=>({receipt:x.receipt,date:x.date,sold_by:x.soldBy,payment:x.payment,total:x.total,net_total:x.netTotal,status:saleStatus(x),items_json:JSON.stringify(x.items||[])}));
 if(format==='json')_nitramDownload(JSON.stringify({format:'NITRAM_SALES',version:1,exportedAt:new Date().toISOString(),sales},null,2),'NITRAM_Sales_History_'+date+'.json','application/json');
 else if(format==='xlsx'){const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(rows),'Sales');XLSX.writeFile(wb,'NITRAM_Sales_History_'+date+'.xlsx')}
 else{const keys=['receipt','date','sold_by','payment','total','net_total','status','items_json'];const values=[keys,...rows.map(x=>keys.map(k=>x[k]??''))];_nitramDownload('\ufeff'+_nitramCsv(values),'NITRAM_Sales_History_'+date+'.csv','text/csv;charset=utf-8')}
}
'@
$app = [regex]::Replace($app,'(?s)function exportProductsBackup\(format\)\{.*?(?=function exportSalesBackup\()', [System.Text.RegularExpressions.MatchEvaluator]{param($m)$productsFn+[Environment]::NewLine},1)
$app = [regex]::Replace($app,'(?s)function exportSalesBackup\(format\)\{.*?(?=function chooseBackupImport\()', [System.Text.RegularExpressions.MatchEvaluator]{param($m)$salesFn+[Environment]::NewLine},1)
$app = $app.Replace("input.accept='.json,.csv,.tsv,.txt,.xml,application/json,text/csv,text/tab-separated-values,text/plain,application/xml'","input.accept='.json,.csv,.tsv,.txt,.xml,.xlsx,application/json,text/csv,text/tab-separated-values,text/plain,application/xml,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'")

$importFn = @'
async function importPortableBackup(event,kind){
 const file=event.target.files?.[0];if(!file)return;
 try{
  let data,rows;
  if(file.name.toLowerCase().endsWith('.xlsx')){if(!window.XLSX)throw Error('Excel support is unavailable');const wb=XLSX.read(await file.arrayBuffer(),{type:'array'});const sheet=wb.Sheets[wb.SheetNames[0]];data=XLSX.utils.sheet_to_json(sheet,{defval:''})}
  else{const text=String(await file.text()).replace(/^\ufeff/,'').trim();if(file.name.toLowerCase().endsWith('.json')||/^[\[{]/.test(text)){data=JSON.parse(text)}else if(file.name.toLowerCase().endsWith('.xml')||text.startsWith('<?xml')){const doc=new DOMParser().parseFromString(text,'application/xml');if(doc.querySelector('parsererror'))throw Error('XML file could not be read');data=[...doc.querySelectorAll('row,product,sale,item')].map(el=>Object.fromEntries([...el.children].map(n=>[n.tagName,n.textContent])))}else{const delimiter=(text.split(/\r?\n/,1)[0].split('\t').length>text.split(/\r?\n/,1)[0].split(',').length)?'\t':',';rows=_nitramParseDelimited(text,delimiter);const heads=(rows.shift()||[]).map(x=>x.trim());data=rows.map(row=>Object.fromEntries(heads.map((h,i)=>[h,row[i]??''])))}}
  if(kind==='products'){let list=Array.isArray(data)?data:(data.products||data.items||data.data||data.Products);if(!Array.isArray(list))throw Error('No product records were found in this file');const clean=list.map(_nitramNormalizeProduct).filter(Boolean);if(!clean.length)throw Error('No rows contained a recognizable barcode and product name');const unique=new Map();clean.forEach(p=>unique.set(p.barcode,p));if(!confirm('Replace the current product catalogue with '+unique.size+' imported products? Sales history and other POS records will be retained. Export your current Products backup first if needed.'))return;S.products=[...unique.values()];S.productlist20ImportVersion=2;S.cart=(S.cart||[]).filter(x=>S.products.some(p=>p.id===String(x.id)));save();render('products');toast('Imported '+S.products.length+' products. '+(clean.length-unique.size)+' duplicate barcode rows were merged.')}
  else{let list=Array.isArray(data)?data:(data.sales||data.transactions||data.items||data.data||data.Sales);if(!Array.isArray(list))throw Error('No sales records were found in this file');const existing=new Set((S.sales||[]).map(x=>String(x.receipt||x.id||'')));let added=0;list.forEach(x=>{const receipt=String(x.receipt||x.receipt_no||x.receiptNumber||x.invoice||x.id||'').trim();if(!receipt||existing.has(receipt))return;const total=Number(x.total??x.amount??x.net_total??0);S.sales.push({...x,id:x.id||'IMPORT-'+receipt,receipt,date:x.date||x.timestamp||'',soldBy:x.soldBy||x.sold_by||x.cashier||'Imported',payment:x.payment||x.payment_method||'Unknown',total:Number.isFinite(total)?total:0,items:Array.isArray(x.items)?x.items:(()=>{try{return JSON.parse(x.items_json||x.itemsJson||'[]')}catch{return []}})()});existing.add(receipt);added++});if(!added)throw Error('No new sales were imported. Existing receipt numbers may already be present or the file may lack receipt numbers.');save();render('sales');toast('Imported '+added+' new sales records; duplicates were skipped.')}
 }catch(err){console.error(err);toast('Could not import this file: '+String(err.message||err))}finally{event.target.value=''}
}
'@
$app = [regex]::Replace($app,'(?s)function importPortableBackup\(event,kind\)\{.*?(?=function downloadCSV\()', [System.Text.RegularExpressions.MatchEvaluator]{param($m)$importFn+[Environment]::NewLine},1)
$app = $app.Replace('<option value=json>JSON</option>','<option value=json>JSON</option><option value=xlsx>Excel (.xlsx)</option>')
if (-not $app.Contains("file.name.toLowerCase().endsWith('.xlsx')")) { throw 'Excel import support was not inserted.' }
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
node --check $appPath
if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax check failed after spreadsheet support patch.' }
Write-Host 'Added offline XLSX support for Products and Sales import/export.'
