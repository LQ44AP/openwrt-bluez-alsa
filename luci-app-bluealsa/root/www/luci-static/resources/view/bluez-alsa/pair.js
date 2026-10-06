'use strict';
'require view';
'require fs';
'require ui';

var BT_PAIR = '/usr/bin/bt-pair';

function parseDevices(stdout) {
	var list = [];
	if (!stdout)
		return list;
	stdout.split('\n').forEach(function(line) {
		var m = line.match(/^\s*Device\s+([0-9A-Fa-f:]+)\s+(.+?)\s*$/);
		if (m)
			list.push({ mac: m[1], name: m[2] });
	});
	return list;
}

function callBtPair(args) {
	return fs.exec(BT_PAIR, args).then(function(res) {
		if (res.code !== 0)
			throw new Error((res.stderr || '').trim() || '操作失败');
		return res.stdout || '';
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			callBtPair([ 'list' ]).then(parseDevices).catch(function() { return []; }),
			callBtPair([ 'status' ]).catch(function() { return ''; })
		]);
	},

	render: function(data) {
		var paired   = data[0] || [];
		var statusTx = data[1] || '';
		var self     = this;

		// 解析 status 中的已连接设备
		var connected = [];
		var inConnected = false;
		statusTx.split('\n').forEach(function(line) {
			if (line.indexOf('--- Connected ---') >= 0) { inConnected = true; return; }
			if (inConnected) {
				var m = line.match(/^\s*Device\s+([0-9A-Fa-f:]+)\s+(.+?)\s*$/);
				if (m) connected.push({ mac: m[1], name: m[2] });
			}
		});

		var connectedMacs = {};
		connected.forEach(function(d) { connectedMacs[d.mac.toUpperCase()] = true; });

		// ---------- 已配对设备列表 ----------
		var pairedRows = paired.map(function(d) {
			var isConn = !!connectedMacs[d.mac.toUpperCase()];
			var statusSpan = isConn
				? E('span', { style: 'color:#0a0;font-weight:bold;' }, [ '已连接' ])
				: E('span', { style: 'color:#888;' }, [ '已配对' ]);

			var btnUnpair = E('button', {
				'class': 'btn cbi-button cbi-button-remove',
				'click': function() {
					if (!confirm(_('确定取消与 %s 的配对？').format(d.name)))
						return;
					btnUnpair.disabled = true;
					btnUnpair.textContent = _('处理中…');
					callBtPair([ 'unpair', d.mac ]).then(function() {
						ui.addNotification(null, E('p', [ _('已取消配对：') + d.name ]), 'info');
						self.refresh();
					}).catch(function(err) {
						ui.addNotification(null, E('p', [ _('操作失败：') + err.message ]), 'error');
						btnUnpair.disabled = false;
						btnUnpair.textContent = _('取消配对');
					});
				}
			}, [ _('取消配对') ]);

			var btnConn = isConn
				? E('button', {
					'class': 'btn cbi-button',
					'click': function() {
						btnConn.disabled = true;
						callBtPair([ 'disconnect', d.mac ]).then(function() {
							self.refresh();
						}).catch(function(err) {
							ui.addNotification(null, E('p', [ err.message ]), 'error');
							btnConn.disabled = false;
						});
					}
				}, [ _('断开') ])
				: E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': function() {
						btnConn.disabled = true;
						callBtPair([ 'connect', d.mac ]).then(function() {
							ui.addNotification(null, E('p', [ _('已发起连接：') + d.name ]), 'info');
							self.refresh();
						}).catch(function(err) {
							ui.addNotification(null, E('p', [ err.message ]), 'error');
							btnConn.disabled = false;
						});
					}
				}, [ _('连接') ]);

			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'data-title': _('设备') }, [ d.name ]),
				E('td', { 'class': 'td', 'data-title': _('MAC') }, [ E('code', {}, [ d.mac ]) ]),
				E('td', { 'class': 'td', 'data-title': _('状态') }, [ statusSpan ]),
				E('td', { 'class': 'td', 'data-title': _('操作') }, [ btnConn, ' ', btnUnpair ])
			]);
		});

		var pairedTable = paired.length
			? E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, [ _('设备') ]),
					E('th', { 'class': 'th' }, [ _('MAC') ]),
					E('th', { 'class': 'th' }, [ _('状态') ]),
					E('th', { 'class': 'th' }, [ _('操作') ])
				])
			].concat(pairedRows))
			: E('p', { 'class': 'cbi-section-descr' }, [ _('暂无已配对设备。') ]);

		// ---------- 扫描区域 ----------
		var scanResultBox = E('div', { 'style': 'margin-top:1em;' });

		var btnScan = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': function() {
				btnScan.disabled = true;
				btnScan.textContent = _('扫描中…… (最多 15 秒)');
				scanResultBox.innerHTML = '';

				callBtPair([ 'scan' ]).then(function(stdout) {
					var found = parseDevices(stdout);
					var known = {};
					paired.forEach(function(p) { known[p.mac.toUpperCase()] = true; });

					if (found.length === 0) {
						scanResultBox.appendChild(E('p', { 'class': 'cbi-section-descr' },
							[ _('未发现设备。请确认目标设备处于配对模式。') ]));
						return;
					}

					var rows = found.map(function(d) {
						var isPaired = !!known[d.mac.toUpperCase()];
						var btn = E('button', {
							'class': 'btn cbi-button cbi-button-apply',
							'click': function() {
								btn.disabled = true;
								btn.textContent = _('配对中…');
								callBtPair([ 'pair', d.mac ]).then(function() {
									ui.addNotification(null, E('p', [ _('配对成功：') + d.name ]), 'info');
									self.refresh();
								}).catch(function(err) {
									ui.addNotification(null, E('p', [ _('配对失败：') + err.message ]), 'error');
									btn.disabled = false;
									btn.textContent = _('配对');
								});
							}
						}, [ _('配对') ]);

						if (isPaired) {
							btn.disabled = true;
							btn.textContent = _('已配对');
						}

						return E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'data-title': _('设备') }, [ d.name ]),
							E('td', { 'class': 'td', 'data-title': _('MAC') }, [ E('code', {}, [ d.mac ]) ]),
							E('td', { 'class': 'td', 'data-title': _('操作') }, [ btn ])
						]);
					});

					scanResultBox.appendChild(E('table', { 'class': 'table' }, [
						E('tr', { 'class': 'tr table-titles' }, [
							E('th', { 'class': 'th' }, [ _('设备') ]),
							E('th', { 'class': 'th' }, [ _('MAC') ]),
							E('th', { 'class': 'th' }, [ _('操作') ])
						])
					].concat(rows)));
				}).catch(function(err) {
					ui.addNotification(null, E('p', [ _('扫描失败：') + err.message ]), 'error');
				}).finally(function() {
					btnScan.disabled = false;
					btnScan.textContent = _('重新扫描');
				});
			}
		}, [ _('扫描附近设备') ]);

		// ---------- 组装页面 ----------
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('蓝牙配对管理') ]),
			E('div', { 'class': 'cbi-map-descr' },
				[ _('扫描附近蓝牙设备、配对、连接和取消配对。配对后的设备会出现在上方“目标设备”列表中。') ]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('已配对设备') ]),
				pairedTable
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('扫描并配对') ]),
				E('p', { 'class': 'cbi-section-descr' },
					[ _('请先让目标设备进入配对模式，然后点击扫描（约需 15 秒）。') ]),
				E('div', { 'style': 'margin:1em 0;' }, [ btnScan ]),
				scanResultBox
			])
		]);
	},

	// 重新加载当前视图数据
	refresh: function() {
		window.location.reload();
	}
});
