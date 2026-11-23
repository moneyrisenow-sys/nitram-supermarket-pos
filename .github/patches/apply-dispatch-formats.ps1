$ErrorActionPreference = 'Stop'
$project = Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT'
$appPath = Join-Path $project 'dist/app.js'
$app = Get-Content -LiteralPath $appPath -Raw

# Let the sender select JSON, CSV or genuine XLSX for the portable dispatch.
$app = $app.Replace('<h2>Send stock to cashier</h2><p class="muted">Create an offline dispatch file. Stock is deducted from the office immediately; the cashier imports the file to receive it. Each dispatch can only be imported once.</p><label>Cashier / destination<input id="dispatchReceiver"', '<h2>Send stock to cashier</h2><p class="muted">Create an offline dispatch file. Stock is deducted from the office immediately; the cashier imports the file to receive it. Each dispatch can only be imported once.</p><label>File format<select id="dispatchFormat"><option value="json">JSON</option><option value="csv">CSV</option><option value="xlsx">Excel (.xlsx)</option></select></label><label>Cashier / destination<input id="dispatchReceiver"')
$oldDownload = "const blob=new Blob([JSON.stringify(dispatch,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=dispatch.dispatchId+'.nitram-dispatch.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500);"
$newDownload = @'
const format=document.getElementById('dispatchFormat')?.value||'json',stamp=dispatch.dispatchId;
 if(format==='xlsx'){const wb=XLSX.utils.book_new(),meta=XLSX.utils.json_to_sheet([{dispatchId:dispatch.dispatchId,sender:dispatch.sender,receiver:dispatch.receiver,createdAt:dispatch.createdAt,status:dispatch.status}]),items=XLSX.utils.json_to_sheet(dispatch.items.map(x=>({productId:x.productId,name:x.name,barcode:x.barcode,quantity:x.quantity})));XLSX.utils.book_append_sheet(wb,meta,'Dispatch');XLSX.utils.book_append_sheet(wb,items,'Items');XLSX.writeFile(wb,stamp+'.nitram-dispatch.xlsx')}
 else if(format==='csv'){const rows=[['dispatch_id','sender','receiver','created_at','status','product_id','name','barcode','quantity'],...dispatch.items.map(x=>[dispatch.dispatchId,dispatch.sender,dispatch.receiver,dispatch.createdAt,dispatch.status,x.productId,x.name,x.barcode,x.quantity])];_nitramDownload('\ufeff'+_nitramCsv(rows),stamp+'.nitram-dispatch.csv','text/csv;charset=utf-8')}
 else{const blob=new Blob([JSON.stringify(dispatch,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=stamp+'.nitram-dispatch.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500)}
'@
if ($app.Contains($oldDownload)) { $app = $app.Replace($oldDownload,$newDownload) } else { throw 'Dispatch download block was not found.' }

# Parse the three supported portable formats while preserving dispatch identity and product IDs.
$oldParse = "const data=JSON.parse(await file.text());if(data.schema!=='NITRAM-STOCK-DISPATCH'||data.version!==1||!data.dispatchId||!Array.isArray(data.items)||!data.items.length)throw new Error('This is not a valid NITRAM dispatch file.');"
$newParse = @'
let data;
  if(file.name.toLowerCase().endsWith('.xlsx')){const wb=XLSX.read(await file.arrayBuffer(),{type:'array'}),meta=XLSX.utils.sheet_to_json(wb.Sheets.Dispatch||wb.Sheets[wb.SheetNames[0]],{defval:''})[0]||{},items=XLSX.utils.sheet_to_json(wb.Sheets.Items||wb.Sheets[wb.SheetNames[1]],{defval:''});data={schema:'NITRAM-STOCK-DISPATCH',version:1,dispatchId:meta.dispatchId,sender:meta.sender,receiver:meta.receiver,createdAt:meta.createdAt,status:meta.status,items:items.map(x=>({productId:String(x.productId),name:x.name,barcode:x.barcode,quantity:Number(x.quantity)}))}}
  else if(file.name.toLowerCase().endsWith('.csv')){const rows=_nitramParseDelimited(await file.text().replace(/^\ufeff/,''),','),heads=(rows.shift()||[]).map(x=>x.trim()),list=rows.map(row=>Object.fromEntries(heads.map((h,i)=>[h,row[i]??''])));if(!list.length)throw new Error('Dispatch CSV has no item rows');const first=list[0];data={schema:'NITRAM-STOCK-DISPATCH',version:1,dispatchId:first.dispatch_id,sender:first.sender,receiver:first.receiver,createdAt:first.created_at,status:first.status,items:list.map(x=>({productId:String(x.product_id),name:x.name,barcode:x.barcode,quantity:Number(x.quantity)}))}}
  else{data=JSON.parse(await file.text())}
  if(data.schema!=='NITRAM-STOCK-DISPATCH'||data.version!==1||!data.dispatchId||!Array.isArray(data.items)||!data.items.length)throw new Error('This is not a valid NITRAM dispatch file.');
'@
if ($app.Contains($oldParse)) { $app = $app.Replace($oldParse,$newParse) } else { throw 'Dispatch JSON parser marker was not found.' }

Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
node --check $appPath
if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax check failed after multi-format dispatch patch.' }
Write-Host 'Added JSON, CSV and XLSX stock dispatch export/import.'
