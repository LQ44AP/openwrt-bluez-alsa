'use strict';
'require view';
'require form';
'require fs';
'require rpc';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} }
});

function parseBtDevices(stdout) {
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

function isServiceRunning(svclist) {
	try {
		var info = svclist['bluealsa'];
		if (!info)
			return false;
		var instances = info.instances || {};
		for (var k in instances)
			if (instances[k] && instances[k].running)
				return true;
	} catch (e) {}
	return false;
}

return view.extend({
	load: function() {
		return Promise.all([
			callServiceList('bluealsa').catch(function() { return {}; }),
			fs.exec('/usr/bin/bluetoothctl', [ 'list' ])
				.catch(function() { return { stdout: '' }; }),
			fs.exec('/usr/bin/bluetoothctl', [ 'devices', 'Paired' ])
				.catch(function() { return { stdout: '' }; }),
			fs.exec('/usr/bin/bluetoothctl', [ 'devices' ])
				.catch(function() { return { stdout: '' }; }),
			fs.exec('/usr/bin/bluetoothctl', [ 'devices', 'Connected' ])
				.catch(function() { return { stdout: '' }; })
		]).then(function(data) {
			var svclist   = data[0] || {};
			var ctlOut    = (data[1] && data[1].stdout) || '';
			var paired    = parseBtDevices(data[2] && data[2].stdout);
			var allKnown  = parseBtDevices(data[3] && data[3].stdout);
			var connected = parseBtDevices(data[4] && data[4].stdout);

			if (paired.length === 0)
				paired = allKnown;

			// 解析 "Controller AA:BB:CC:DD:EE:FF Name [default]"
			// 输出顺序即控制器索引顺序：第 1 行是 hci0，第 2 行是 hci1……
			var hciList = [];
			var idx = 0;
			ctlOut.split('\n').forEach(function(line) {
				var m = line.match(/^\s*Controller\s+([0-9A-Fa-f:]+)\s+(.*?)\s*$/);
				if (m) {
					var name = m[2].replace(/\s*\[default\]\s*$/, '');
					hciList.push({
						name: 'hci' + idx,
						address: m[1],
						label: name
					});
					idx++;
				}
			});

			return {
				svclist:   svclist,
				hciList:   hciList,
				paired:    paired,
				connected: connected
			};
		});
	},

	render: function(data) {
		var svclist   = data.svclist || {};
		var hciList   = data.hciList || [];
		var paired    = data.paired || [];
		var connected = data.connected || [];
		var running   = isServiceRunning(svclist);

		var m, s, o;

		m = new form.Map('bluealsa',
			_('蓝牙音频配置'),
			_('管理 BlueALSA 服务及设备自动重连'));

		// ============================================================
		// 基础设置
		// ============================================================
		s = m.section(form.NamedSection, 'main', 'bluealsa', _('基础设置'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.DummyValue, '_status', _('服务状态'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return running
				? '<span style="color:#0a0;font-weight:bold;">● 运行中</span>'
				: '<span style="color:#c00;">○ 已停止</span>';
		};

		o = s.option(form.Flag, 'enabled', _('启用服务'),
			_('启动 BlueALSA 守护进程（bluealsad）'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'device_name', _('蓝牙显示名称'),
			_('对外广播的设备名称'));
		o.default = 'OpenWrt-BT';
		o.placeholder = 'OpenWrt-BT';
		o.rmempty = false;

		o = s.option(form.Flag, 'sink_enabled', _('接收模式 (Sink)'),
			_('手机 → 路由器：接收其他设备推送的音频并在本地播放'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'source_enabled', _('发射模式 (Source)'),
			_('路由器 → 蓝牙音箱：主动连接蓝牙耳机/音箱并推送音频'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'aac_afterburner', _('启用 AAC 编解码'),
			_('需要 fdk-aac 软件包。如果服务启动失败，请尝试关闭此项'));
		o.default = '1';
		o.rmempty = false;

		// ---- 动态 HCI 设备列表 ----
		o = s.option(form.ListValue, 'hci', _('HCI 设备'),
			_('选择要使用的蓝牙适配器'));
		o.rmempty = false;
		if (hciList.length === 0) {
			o.value('hci0', 'hci0 (未检测到适配器，请检查 bluez-daemon 是否运行)');
			o.default = 'hci0';
		} else {
			hciList.forEach(function(h) {
				o.value(h.name, h.name + '  [' + h.address + ']  ' + h.label);
			});
			o.default = hciList[0].name;
		}

		o = s.option(form.Flag, 'sysbus', _('使用系统 D-Bus'),
			_('OpenWrt 上通常必须启用，否则 bluealsad 无法发现蓝牙设备'));
		o.default = '1';
		o.rmempty = false;

		// ============================================================
		// 自动连接设置
		// ============================================================
		s = m.section(form.NamedSection, 'settings', 'bluetooth',
			_('自动连接设置'),
			_('发射模式下，后台脚本会持续监控并自动重连指定的蓝牙设备'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.DummyValue, '_connected', _('已连接设备'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			if (connected.length === 0)
				return '<span style="color:#888;">（无）</span>';
			return connected.map(function(d) {
				return d.name + ' [' + d.mac + ']';
			}).join('<br/>');
		};

		o = s.option(form.Flag, 'enabled', _('启用自动重连'),
			_('后台监控目标设备，断开后自动重连'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.ListValue, 'mac', _('目标设备'),
			_('从已配对的蓝牙设备中选择；若列表为空，请先在“蓝牙”页面配对'));
		o.value('', _('-- 请选择 --'));
		o.rmempty = false;
		o.depends('enabled', '1');
		o.datatype = 'macaddr';

		paired.forEach(function(d) {
			o.value(d.mac, d.name + '  [' + d.mac + ']');
		});

		// ============================================================
		// 监控参数
		// ============================================================
		s = m.section(form.NamedSection, 'monitor', 'monitor',
			_('监控参数'),
			_('调整自动重连脚本的行为。不当的设置可能导致连接不稳定'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Value, 'scan_duration', _('扫描持续时间 (秒)'),
			_('每次扫描附近蓝牙设备的时间'));
		o.datatype = 'uinteger';
		o.default = '8';
		o.rmempty = false;

		o = s.option(form.Value, 'ping_timeout', _('Ping 超时 (秒)'),
			_('l2ping 探测目标设备的超时时间'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = s.option(form.Value, 'connect_wait_max', _('连接最大等待 (秒)'),
			_('发起连接后等待确认的最长时间'));
		o.datatype = 'uinteger';
		o.default = '20';
		o.rmempty = false;

		o = s.option(form.Value, 'disconnected_sleep', _('断开后休眠 (秒)'),
			_('未连接时两次探测之间的间隔'));
		o.datatype = 'uinteger';
		o.default = '30';
		o.rmempty = false;

		o = s.option(form.Value, 'connected_sleep', _('已连接轮询 (秒)'),
			_('已连接时检查状态的间隔'));
		o.datatype = 'uinteger';
		o.default = '20';
		o.rmempty = false;

		o = s.option(form.Flag, 'clean_other_devices', _('断开其他设备'),
			_('开启后会主动断开所有非目标蓝牙设备（包括键鼠），请谨慎启用'));
		o.default = '0';
		o.rmempty = false;

		return m.render();
	}
});