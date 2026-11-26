$ErrorActionPreference = 'Stop'
$project = Join-Path $env:GITHUB_WORKSPACE 'NITRAM_TAURI_SQLITE_PROJECT'
$appPath = Join-Path $project 'dist/app.js'
$htmlPath = Join-Path $project 'dist/index.html'
$app = Get-Content -LiteralPath $appPath -Raw
$html = Get-Content -LiteralPath $htmlPath -Raw
$stockNav = '<button title="Stock" onclick="go(''stock'',this)"><span class="nav-icon">📊</span><span class="nav-label">Stock</span></button>'
$dispatchNav = $stockNav + '<button title="Dispatch" onclick="go(''dispatch'',this)"><span class="nav-icon">⇄</span><span class="nav-label">Dispatch</span></button>'
if (-not $html.Contains('title="Dispatch"')) { if (-not $html.Contains($stockNav)) { throw 'Stock navigation item not found.' }; $html = $html.Replace($stockNav,$dispatchNav) }
if (-not $html.Contains('title="Dispatch"')) { throw 'Dedicated Dispatch navigation item was not added.' }
$roleOld = "Owner:['sale','held','sales','products','stock','supplier','expenses','dashboard','shifts','settings'],Admin:"
$roleNew = "Owner:['sale','held','sales','products','stock','dispatch','supplier','expenses','dashboard','shifts','settings'],Admin:"
if ($app.Contains($roleOld)) { $app = $app.Replace($roleOld,$roleNew) }
$cashierOld = "Cashier:['sale','held','sales','stock','expenses','shifts']"
$cashierNew = "Cashier:['sale','held','sales','stock','dispatch','expenses','shifts']"
if ($app.Contains($cashierOld)) { $app = $app.Replace($cashierOld,$cashierNew) }
if (-not $app.Contains($roleNew) -or -not $app.Contains($cashierNew)) { throw 'Owner/Cashier Dispatch permissions could not be applied.' }
$navOld = "'Stock':'stock','Supplier':'supplier'"
$navNew = "'Stock':'stock','Dispatch':'dispatch','Supplier':'supplier'"
if ($app.Contains($navOld)) { $app = $app.Replace($navOld,$navNew) }
if (-not $app.Contains($navNew)) { throw 'Dispatch navigation mapping could not be applied.' }
$viewsOld = "products:()=>products(),stock:()=>stock(),supplier:()=>supplier()"
$viewsNew = "products:()=>products(),stock:()=>stock(),dispatch:()=>dispatch(),supplier:()=>supplier()"
if ($app.Contains($viewsOld)) { $app = $app.Replace($viewsOld,$viewsNew) }
if (-not $app.Contains($viewsNew)) { throw 'Dispatch page was not registered in render().' }
$dispatchPage = @'
function dispatch(){
 const owner=S.activeRole==='Owner',cashier=S.activeRole==='Cashier';
 const eligible=owner?_nitramReceivedMovements():[];
 const total=eligible.reduce((n,x)=>n+x.quantity,0);
 const history=(S.stockDispatches||[]).slice(0,30);
 const historyRows=history.map(x=>'<tr><td>'+escapeScanHtml(x.dispatchId)+'</td><td>'+escapeScanHtml(x.receiver||x.sender||'—')+'</td><td>'+escapeScanHtml(x.createdAt||'—')+'</td><td>'+escapeScanHtml(x.status||'sent')+'</td><td>'+((x.acknowledgement||x.status==='received')?'Received':'Awaiting acknowledgement')+'</td></tr>').join('');
 return '<div class=title><div><h1>Dispatch</h1><p>Transfer newly received stock from the Owner database to the cashier and reconcile the receipt.</p></div></div>'+
 '<div class=cards><div class=card><div class=muted>Eligible receipt lines</div><div class=metric>'+eligible.length+'</div></div><div class=card><div class=muted>Units available to dispatch</div><div class=metric>'+total+'</div></div><div class=card><div class=muted>Recorded dispatches</div><div class=metric>'+history.length+'</div></div></div>'+
 (owner?'<div class=panel style="margin-top:14px"><h2>Dispatch newly received stock</h2><p class=muted>Only positive quantities recorded with the Delivery received reason are eligible. Already-dispatched quantities are excluded automatically.</p><label style="display:block;max-width:360px">Cashier / destination<input id=dispatchReceiver class=field value="'+escapeScanHtml(S.dispatchReceiver||S.defaultCashier||'Cashier')+'" placeholder="Cashier or till name" style="width:100%"></label><div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px"><button class=btn onclick="dispatchNewlyReceivedStock()">Dispatch eligible stock</button><label class=ghost style="display:inline-flex;align-items:center;gap:6px;cursor:pointer">Import cashier acknowledgement<input type=file accept=".json,application/json" style="display:none" onchange="importStockDispatch(event)"></label></div><div style="margin-top:14px"><b>Eligible items</b><div style="overflow-x:auto"><table class=table><thead><tr><th>Product</th><th>Barcode</th><th>Received</th><th>Available to dispatch</th></tr></thead><tbody>'+(eligible.map(x=>'<tr><td>'+escapeScanHtml(x.name)+'</td><td>'+escapeScanHtml(x.barcode)+'</td><td>'+x.sourceQuantity+'</td><td><b>'+x.quantity+'</b></td></tr>').join('')||'<tr><td colspan=4 class=muted>No undispatched received stock is currently available.</td></tr>')+'</tbody></table></div></div></div>':'')+
 (cashier?'<div class=panel style="margin-top:14px"><h2>Receive stock dispatch</h2><p class=muted>Choose the dispatch file sent by the Owner. Verify the physical quantities before confirming receipt.</p><label class=btn style="display:inline-flex;cursor:pointer">Choose dispatch file<input type=file accept=".json,application/json,.csv,text/csv,.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" style="display:none" onchange="importStockDispatch(event)"></label></div>':'')+
 '<div class=title style="margin-top:20px"><div><h2>Dispatch history</h2><p>Transfers recorded on this computer.</p></div></div><div class=panel><div style="overflow-x:auto"><table class=table><thead><tr><th>Dispatch reference</th><th>Other party</th><th>Date</th><th>Status</th><th>Reconciliation</th></tr></thead><tbody>'+(historyRows||'<tr><td colspan=5 class=muted style="text-align:center;padding:24px">No dispatches recorded yet.</td></tr>')+'</tbody></table></div></div>';
}
'@
if (-not $app.Contains('function dispatch(){')) { $marker='function stockRows(items)'; if (-not $app.Contains($marker)) { throw 'Stock page insertion point missing.' }; $app=$app.Replace($marker,$dispatchPage+[Environment]::NewLine+$marker) }
$focusOld = "products:'productSearch',"
$focusNew = "products:'productSearch',dispatch:'dispatchReceiver',"
if ($app.Contains($focusOld) -and -not $app.Contains($focusNew)) { $app=$app.Replace($focusOld,$focusNew) }
$app = [regex]::Replace($app,'<div style="display:flex;gap:8px;flex-wrap:wrap"><button class=ghost onclick="openStockDispatchImport\(\)">Import Dispatch</button><button class=btn onclick="openStockDispatch\(\)">Send Stock to Cashier</button><button class=ghost onclick="openStockAdjustment\(\)">Adjust Stock</button><input id="stockDispatchFile"[^>]*></div>','<button class=ghost onclick="openStockAdjustment()">Adjust Stock</button>')
$app = [regex]::Replace($app,'<div style="display:flex;gap:8px;flex-wrap:wrap"><button class=ghost onclick="openStockDispatchImport\(\)">Import Dispatch</button><button class=btn onclick="dispatchNewlyReceivedStock\(\)">Dispatch Newly Received</button><button class=ghost onclick="openStockAdjustment\(\)">Adjust Stock</button><input id="stockDispatchFile"[^>]*></div>','<button class=ghost onclick="openStockAdjustment()">Adjust Stock</button>')
$app = $app.Replace("const receiver=String(S.dispatchReceiver||S.defaultCashier||'Cashier').trim()||'Cashier';","const receiver=String(document.getElementById('dispatchReceiver')?.value||S.dispatchReceiver||S.defaultCashier||'Cashier').trim()||'Cashier';S.dispatchReceiver=receiver;")
$app = $app.Replace("render('stock');toast('Newly received stock dispatched. Send the downloaded file to the cashier.');","render('dispatch');toast('Newly received stock dispatched. Send the downloaded file to the cashier.');")
Set-Content -LiteralPath $htmlPath -Value $html -NoNewline -Encoding utf8
Set-Content -LiteralPath $appPath -Value $app -NoNewline -Encoding utf8
node --check $appPath
if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax validation failed after dedicated Dispatch tab patch.' }
if (-not (Select-String -LiteralPath $htmlPath -Pattern 'title="Dispatch"' -Quiet)) { throw 'Final shell validation failed: Dispatch tab missing.' }
if (-not (Select-String -LiteralPath $appPath -Pattern 'function dispatch\(\)' -Quiet)) { throw 'Final app validation failed: Dispatch view missing.' }
if (-not (Select-String -LiteralPath $appPath -Pattern 'dispatch:\(\)=>dispatch\(\)' -Quiet)) { throw 'Final app validation failed: Dispatch renderer missing.' }
if (-not (Select-String -LiteralPath $appPath -Pattern "'Dispatch':'dispatch'" -Quiet)) { throw 'Final app validation failed: Dispatch navigation mapping missing.' }
Write-Host 'Dedicated Dispatch tab added; Owner dispatch, Cashier receipt import and acknowledgement import are exposed on that page.'
