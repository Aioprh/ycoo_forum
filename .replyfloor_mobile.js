function replyfloor_seccodeimg(obj) {
	document.getElementById('replyfloor_seccodeverify').value = '';
	var tmprandom = 'S' + Math.floor(Math.random() * 1000);
	obj.src = 'misc.php?mod=seccode&update='+ tmprandom+'&idhash=replyfloor';
}
function replyfloor_strLenCalc(obj, checklen, maxlen) {
	var v = obj.value, charlen = 0, maxlen = !maxlen ? 200 : maxlen, curlen = maxlen, len = v.length;
	for(var i = 0; i < v.length; i++) {
		if(v.charCodeAt(i) < 0 || v.charCodeAt(i) > 255) {
			curlen -= charset == 'utf-8' ? 2 : 1;
		}
	}
	if(curlen >= len) {
		document.getElementById(checklen).innerHTML = curlen - len;
	} else {
		len = 0;
		var ret = '';
		for(var i = 0; i < v.length; i++) {
			len += v.charCodeAt(i) < 0 || v.charCodeAt(i) > 255 ? (charset == 'utf-8' ? 3 : 2) : 1;
			if(len > maxlen) {
				break;
			}
			ret += v.substr(i, 1);
		}
		obj.value = ret;
		document.getElementById(checklen).innerHTML = 0;
	}
}
function replyfloor_insertunit(key, text, textend, moveend, selappend) {
	if(document.getElementById(key + 'message')) {
		document.getElementById(key + 'message').focus();
	}
	textend = isUndefined(textend) ? '' : textend;
	moveend = isUndefined(textend) ? 0 : moveend;
	selappend = isUndefined(selappend) ? 1 : selappend;
	startlen = text.length;
	endlen = textend.length;
	if(!isUndefined(document.getElementById(key + 'message').selectionStart)) {
		if(selappend) {
			var opn = document.getElementById(key + 'message').selectionStart + 0;
			if(textend != '') {
				text = text + document.getElementById(key + 'message').value.substring(document.getElementById(key + 'message').selectionStart, document.getElementById(key + 'message').selectionEnd) + textend;
			}
			document.getElementById(key + 'message').value = document.getElementById(key + 'message').value.substr(0, document.getElementById(key + 'message').selectionStart) + text + document.getElementById(key + 'message').value.substr(document.getElementById(key + 'message').selectionEnd);
			if(!moveend) {
				document.getElementById(key + 'message').selectionStart = opn + text.length - endlen;
				document.getElementById(key + 'message').selectionEnd = opn + text.length - endlen;
			}
		} else {
			text = text + textend;
			document.getElementById(key + 'message').value = document.getElementById(key + 'message').value.substr(0, document.getElementById(key + 'message').selectionStart) + text + document.getElementById(key + 'message').value.substr(document.getElementById(key + 'message').selectionEnd);
		}
	} else if(document.selection && document.selection.createRange) {
		var sel = document.selection.createRange();
		if(!sel.text.length && document.getElementById(key + 'message').sel) {
			sel = document.getElementById(key + 'message').sel;
			document.getElementById(key + 'message').sel = null;
		}
		if(selappend) {
			if(textend != '') {
				text = text + sel.text + textend;
			}
			sel.text = text.replace(/\r?\n/g, '\r\n');
			if(!moveend) {
				sel.moveStart('character', -endlen);
				sel.moveEnd('character', -endlen);
			}
			sel.select();
		} else {
			sel.text = text + textend;
		}
	} else {
		document.getElementById(key + 'message').value += text;
	}
	if(document.getElementById(key + 'message').onchange){
		document.getElementById(key + 'message').onchange();
	}
}
function replyfloor_showcolorbox(key, bgcolor) {
	var tag1 = !bgcolor ? 'color' : 'backcolor', tag2 = !bgcolor ? 'forecolor' : 'backcolor';
	var coloroptions = ['Black', 'Sienna', 'DarkOliveGreen', 'DarkGreen', 'DarkSlateBlue', 'Navy', 'Indigo', 'DarkSlateGray', 'DarkRed', 'DarkOrange', 'Olive', 'Green', 'Teal', 'Blue', 'SlateGray', 'DimGray', 'Red', 'SandyBrown', 'YellowGreen', 'SeaGreen', 'MediumTurquoise', 'RoyalBlue', 'Purple', 'Gray', 'Magenta', 'Orange', 'Yellow', 'Lime', 'Cyan', 'DeepSkyBlue', 'DarkOrchid', 'Silver', 'Pink', 'Wheat', 'LemonChiffon', 'PaleGreen', 'PaleTurquoise', 'LightBlue', 'Plum', 'White'];
	var colortexts = ['黑色', '赭色', '暗橄榄绿色', '暗绿色', '暗灰蓝色', '海军色', '靛青色', '墨绿色', '暗红色', '暗桔黄色', '橄榄色', '绿色', '水鸭色', '蓝色', '灰石色', '暗灰色', '红色', '沙褐色', '黄绿色', '海绿色', '间绿宝石', '皇家蓝', '紫色', '灰色', '红紫色', '橙色', '黄色', '酸橙色', '青色', '深天蓝色', '暗紫色', '银色', '粉色', '浅黄色', '柠檬绸色', '苍绿色', '苍宝石绿', '亮蓝色', '洋李色', '白色'];
	var str = '';
	for(var i = 0; i < 40; i++) {
		str += '<span><button type="button" style="background-color: ' + coloroptions[i] + '" onclick="'
			+ 'replyfloor_insertunit(\'' + key + '\', \'[' + tag1 + '=' + coloroptions[i] + ']\', \'[/' + tag1 + ']\')'
			+ '" title="' + colortexts[i] + '"></button></span>';
	}
	if(document.getElementById(key + 'attribute').className == 'replyfloor_showcolorbox'){
		if(document.getElementById(key + 'attribute').innerHTML){
			document.getElementById(key + 'attribute').innerHTML = '';
		}else{
			document.getElementById(key + 'attribute').innerHTML = str;
		}
	}else{
		document.getElementById(key + 'attribute').className = 'replyfloor_showcolorbox';
		document.getElementById(key + 'attribute').innerHTML = str;
	}
}
function replyfloor_showsmilebox(key) {
	if(typeof smilies_type == 'undefined') {
		var scriptNode = document.createElement("script");
		scriptNode.type = "text/javascript";
		scriptNode.charset = charset ? charset : (navigator.userAgent.toLowerCase().indexOf('firefox') != -1 ? document.characterSet : document.charset);
		scriptNode.src = 'data/cache/common_smilies_var.js?' + VERHASH;
		document.getElementsByTagName('head')[0].appendChild(scriptNode);
		scriptNode.onload = function() {
			replyfloor_smilies_onload(key);
		};
	} else {
		replyfloor_smilies_onload(key);
	}
}
function replyfloor_smilies_onload(key) {
	if(typeof smilies_type == 'object') {
		for(i in smilies_array) {
			type = i;break;
		}
		str = '<div id="' + key + 'showsmilebox_tab" class="replyfloor_showsmilebox_tab"><ul>';
		for(i in smilies_type) {
			if(smilies_type[i][0]) {
				str += '<li id="'+key+'showsmilebox_tab'+i+'" onclick="replyfloor_smilies_switch(\'' + key + '\', \'' + i.substring(1) + '\');">'+smilies_type[i][0]+'</li>';
			}
		}
		str += '</ul></div><div id="' + key + 'showsmilebox_data" class="replyfloor_showsmilebox_data"></div>';
		if(document.getElementById(key + 'attribute').className == 'replyfloor_showsmilebox'){
			if(document.getElementById(key + 'attribute').innerHTML){
				document.getElementById(key + 'attribute').innerHTML = '';
			}else{
				document.getElementById(key + 'attribute').innerHTML = str;
				replyfloor_smilies_switch(key, type);
			}
		}else{
			document.getElementById(key + 'attribute').className = 'replyfloor_showsmilebox';
			document.getElementById(key + 'attribute').innerHTML = str;
			replyfloor_smilies_switch(key, type);
		}
	}
}
function replyfloor_smilies_switch(key, type) {
	if(!smilies_array[type]) return;
	smiliesdata = '';
	j = k = 0;
	img = [];
	for(i in smilies_type) {
		if(smilies_type[i][0]) {
			if(type == i.substring(1)) {
				document.getElementById(key + 'showsmilebox_tab'+i).className = 'current';
			}else{
				document.getElementById(key + 'showsmilebox_tab'+i).className = '';
			}
		}
	}
	for(page in smilies_array[type]) {
		for(var i = 0; i < smilies_array[type][page].length; i++) {
			s = smilies_array[type][page][i];
			smilieimg = STATICURL + 'image/smiley/' + smilies_type['_' + type][1] + '/' + s[2];
			img[k] = new Image();
			img[k].src = smilieimg;
			smiliesdata += s && s[0] ? '<span><img class="replyfloor_showsmilebox_img" style="margin:0;" width="' + s[3] +'" height="' + s[4] +'" src="' + smilieimg + '" alt="' + s[1] + '" onclick="replyfloor_insertunit(\'' + key + '\', \'' + s[1].replace(/'/, '\\\'') + '\')" /></span>' : '';
			j++;k++;
		}
	}
	document.getElementById(key + 'showsmilebox_data').innerHTML = smiliesdata;
}

function replyfloor_collapse(obj, postid, type) {
	document.getElementById('replyfloor_content_more_'+postid).innerHTML = '';
	if(type == 1){
		var nextpageurl = obj.getAttribute('rel').valueOf();
		$.get(nextpageurl + '&inajax=1', function(s){
			s = s.lastChild.firstChild.nodeValue;
			s = s.replace(/\n|\r/g, ' ');
			var nexts = s.match(/\<div class="replyfloor_content_li" id="replyfloor_content_li_(\d+)"\>(.+?)\<div>\<\/div>\<\/div>/g);
			for(i in nexts) {
				var insertid = nexts[i].match(/<div class="replyfloor_content_li" id="replyfloor_content_li_(\d+)"\>/);
				if(!document.getElementById('replyfloor_content_li_' + insertid[1])) {
					var div = document.createElement('div');
					document.getElementById('replyfloor_newbox_'+postid).appendChild(div);
					div.outerHTML = nexts[i].replace(/\<div>\<\/div>/g, '');
				}
			}
			var moreinfo = s.match(/\<div class="replyfloor_content_more" id="replyfloor_content_more_(\d+)"\>(.+?)\<div>\<\/div>\<\/div\>/);
			if(document.getElementById('replyfloor_content_more_'+postid)){
				document.getElementById('replyfloor_content_more_'+postid).innerHTML = moreinfo[2];
			}
		}, "xml");
	}else{
		document.getElementById('replyfloor_newbox_'+postid).innerHTML = '';
		var nextpageurl = obj.getAttribute('rel').valueOf();
		$.get(nextpageurl + '&inajax=1', function(s){
			s = s.lastChild.firstChild.nodeValue;
			if(document.getElementById('replyfloor_content_'+postid)){
				document.getElementById('replyfloor_content_'+postid).innerHTML = s;
			}
			var current = $('#replyfloor_box_'+postid).offset().top;
			if($("html,body").scrollTop() > current){
				$("html,body").stop().animate({
					scrollTop: current
				}, 300);
			}
		}, "xml");
	}
	return false;
}
function replyfloor_uploadimage(userSettings) {
	replyfloor_webupload(userSettings);
}
function replyfloor_uploadattach(userSettings) {
	replyfloor_webupload(userSettings);
}
function replyfloor_webupload(userSettings) {
	var settings = {};
	var ensureDefault = function(settingName, defaultValue) {
		var setting = userSettings[settingName];
		if (setting != undefined) {
			settings[settingName] = setting;
		} else {
			settings[settingName] = defaultValue;
		}
	};
	ensureDefault("auto", false);
	ensureDefault("compress", false);
	ensureDefault("upload_url", "");
	ensureDefault("pick", undefined);
	ensureDefault("dnd", undefined);
	ensureDefault("paste", undefined);
	ensureDefault("accept", null);
	ensureDefault("fileVal", "file");
	ensureDefault("chunked", false);
	ensureDefault("chunkSize", 5242880);
	ensureDefault("post_params", {});
	ensureDefault("threads", 1);
	ensureDefault("fileNumLimit", undefined);
	ensureDefault("fileSingleSizeLimit", undefined);
	ensureDefault("listbox", 'replyfloor_upimage');

	var getBasePath = function() {
		var els = document.getElementsByTagName('script'), src;
		for (var i = 0, len = els.length; i < len; i++) {
			src = els[i].src || '';
			if (/cwebuploader[\w\-\.]*\.js/.test(src)) {
				return src.substring(0, src.lastIndexOf('/') + 1);
			}
		}
		return '';
	};

	var uploader = CWebUploader.create({
		auto: false,
		swf: getBasePath() + 'Uploader.swf',
		compress: settings.compress,
		server: settings.upload_url,
		pick: settings.pick,
		dnd: settings.dnd,
		paste: settings.paste,
		accept: settings.accept,
		fileVal: settings.fileVal,
		chunked: settings.chunked,
		chunkSize: settings.chunkSize,
		formData: settings.post_params,
		threads: settings.threads,
		fileNumLimit: settings.fileNumLimit,
		fileSingleSizeLimit: settings.fileSingleSizeLimit,
		duplicate: true,
		disableWidgets: 'log'
	});
	uploader.on('beforeFileQueued', function(file) {

	});
	uploader.on('fileQueued', function( file ) {
		var eles = document.getElementById(settings.listbox).getElementsByClassName('replyfloor_upimage_li');
		if (settings.fileNumLimit && eles.length >= settings.fileNumLimit) {
			popup.open('最多只能上传' +  settings.fileNumLimit + '张', 'alert');
			return false;
		} else {
			var div = document.createElement("div");
			div.id = 'replyfloor_upimage_li_'+file.id;
			div.className = 'replyfloor_upimage_li';
			document.getElementById(settings.listbox).appendChild(div);
			uploader.upload(file);
		}
	});
	uploader.on('uploadSuccess', function( file, response ) {
		var obj = document.getElementById('replyfloor_upimage_li_'+file.id);
		if(response['status'] == 0) {
			obj.parentNode.removeChild(obj);
			popup.open(response['message'], 'alert');
		} else {
			obj.innerHTML = '<div class="replyfloor_upimage_del"><a id="replyfloor_upimage_del_'+response['aid']+'" href="javascript:;" onclick="replyfloor_delimage('+response['aid']+')" title="删除"></a></div><div class="replyfloor_upimage_img"><img src="'+response['attachment']+'" border="0" alt="'+response['filename']+'"/></div><input type="hidden" name="attach[]" value="'+response['aid']+'" />';
		}
	});
	uploader.on("uploadError", function (file, response) {
		var obj = document.getElementById('replyfloor_upimage_li_'+file.id);
		obj.parentNode.removeChild(obj);
	});
	uploader.on("uploadFinished", function () {
		uploader.reset();
	});
	uploader.on('error', function (code) {
		var err = '';
		switch (code) {
			case 'F_EXCEED_SIZE':
				err += '单张图片大小不得超过' +  Base.formatSize(uploader.option('fileSingleSizeLimit')) + '！';
				break;
			case 'Q_EXCEED_NUM_LIMIT':
				err += '最多只能上传' +  settings.fileNumLimit + '张！';
				break;
			case 'Q_EXCEED_SIZE_LIMIT':
				err += '上传图片总大小超出' +  Base.formatSize(uploader.option('fileSizeLimit')) + '！';
				break;
			case 'Q_TYPE_DENIED':
				err += '无效图片类型，请上传正确的图片格式！';
				break;
			case 'F_DUPLICATE':
				err += '请不要重复上传相同图片！';
				break;
			default:
				err += '上传错误，请刷新重试！'+code;
				break;
		}
		popup.open(err, 'alert');
		return false;
	});
}
function replyfloor_plupload(userSettings) {
	var settings = {};
	var ensureDefault = function(settingName, defaultValue) {
		var setting = userSettings[settingName];
		if (setting != undefined) {
			settings[settingName] = setting;
		} else {
			settings[settingName] = defaultValue;
		}
	};
	ensureDefault("auto", false);
	ensureDefault("upload_url", "");
	ensureDefault("pick", undefined);
	ensureDefault("accept", null);
	ensureDefault("fileVal", "file");
	ensureDefault("post_params", {});
	ensureDefault("listbox", 'replyfloor_upimage');

    var pluploader = new plupload.Uploader({
        browse_button : settings.pick,
        url : settings.upload_url,
		file_data_name: settings.fileVal,
		multi_selection: false,
	 	multipart_params: settings.post_params,
		filters:settings.accept
    }); 
    pluploader.init();
    pluploader.bind('FilesAdded',function(uploader,files){
		pluploader.start();
    });
    pluploader.bind('FileUploaded', function(uploader,file, res){
		var response = eval('(' + res.response + ')');
		if(response['status'] == 0) {
			showDialog(response['message'], 'alert');
		} else {
			var div = document.createElement("div");
			div.id = 'replyfloor_upimage_li_'+response['aid'];
			div.className = 'replyfloor_upimage_li';
			div.innerHTML = '<div class="replyfloor_upimage_del"><a href="javascript:;" id="replyfloor_upimage_del_'+response['aid']+'" onclick="replyfloor_delimage('+response['aid']+')" title="删除"></a></div><div class="replyfloor_upimage_img"><img src="'+response['attachment']+'" border="0" alt="'+response['filename']+'"/></div><input type="hidden" name="attach[]" value="'+response['aid']+'" />';
			document.getElementById(settings.listbox).appendChild(div);
		}
    });
    pluploader.bind('Error', function(uploader,error){
        showDialog('上传错误，请刷新重试！', 'alert');
    });
	return false;
}
function replyfloor_delimage(aid) {
	var obj = document.getElementById('replyfloor_upimage_del_'+aid).parentNode.parentNode;
	if(obj) {
		obj.parentNode.removeChild(obj);
		$.get('plugin.php?id=replyfloor:attachment&operation=delete&aid='+aid + '&inajax=1', function(s){

		}, "xml");
	}
}
function replyfloor_autotextarea(obj) {
	obj.style.height = '20px';
	obj.style.height = obj.scrollHeight + 'px';
}

function replyfloor_bbcode2html(str) {
	if(str == '') {
		return '';
	}
	str = str.replace(/</g, '&lt;');
	str = str.replace(/>/g, '&gt;');
	if(typeof smilies_type == 'object') {
		for(var typeid in smilies_array) {
			for(var page in smilies_array[typeid]) {
				for(var i in smilies_array[typeid][page]) {
					re = new RegExp(preg_quote(smilies_array[typeid][page][i][1]), "g");
					str = str.replace(re, '<img src="' + STATICURL + 'image/smiley/' + smilies_type['_' + typeid][1] + '/' + smilies_array[typeid][page][i][2] + '" border="0" smilieid="' + smilies_array[typeid][page][i][0] + '" alt="' + smilies_array[typeid][page][i][1] + '" />');
				}
			}
		}
	}
	str = str.replace(/\[color=([\w#\(\),\s]+?)\]/ig, '<font color="$1">');
	str = preg_replace([
		'\\\[\\\/color\\\]', '\\\[b\\\]', '\\\[\\\/b\\\]'
		], [
		'</font>', '<b>', '</b>'
		], str, 'g');
	str = str.replace(/(^|>)([^<]+)(?=<|$)/ig, function($1, $2, $3) {
		return $2 + preg_replace(['\t', '   ', '  ', '(\r\n|\n|\r)'], ['&nbsp; &nbsp; &nbsp; &nbsp; ', '&nbsp; &nbsp;', '&nbsp;&nbsp;', '<br />'], $3);
	});
	return str;
}

function replyfloor_html2bbcode(str) {
	if(str == '') {
		return '';
	}
	str = preg_replace(['<style.*?>[\\\s\\\S]*?<\/style>', '<script.*?>[\\\s\\\S]*?<\/script>', '<noscript.*?>[\\\s\\\S]*?<\/noscript>', '<select.*?>[\s\S]*?<\/select>', '<object.*?>[\s\S]*?<\/object>', '<!--[\\\s\\\S]*?-->', ' on[a-zA-Z]{3,16}\\\s?=\\\s?"[\\\s\\\S]*?"'], '', str);
	str= str.replace(/(\r\n|\n|\r)/ig, '');
	str= str.replace(/&((#(32|127|160|173))|shy|nbsp);/ig, ' ');
	str = str.replace(/<br\s+?style=(["']?)clear: both;?(\1)[^\>]*>/ig, '');
	str = str.replace(/<br[^\>]*>/ig, "\n");
	str = str.replace(/<img[^>]+smilieid=(["']?)(\d+)(\1)[^>]*>/ig, function($1, $2, $3) {return replyfloor_smileycode($3);});
	str = replyfloor_recursion('b', str, 'replyfloor_simpletag', 'b');
	str = replyfloor_recursion('strong', str, 'replyfloor_simpletag', 'b');
	str = str.replace(/<[\/\!]*?[^<>]*?>/ig, '');
	return preg_replace(['&nbsp;', '&lt;', '&gt;', '&amp;'], [' ', '<', '>', '&'], str);
}

function replyfloor_recursion(tagname, text, dofunction, extraargs) {
	if(extraargs == null) {
		extraargs = '';
	}
	tagname = tagname.toLowerCase();

	var open_tag = '<' + tagname;
	var open_tag_len = open_tag.length;
	var close_tag = '</' + tagname + '>';
	var close_tag_len = close_tag.length;
	var beginsearchpos = 0;

	do {
		var textlower = text.toLowerCase();
		var tagbegin = textlower.indexOf(open_tag, beginsearchpos);
		if(tagbegin == -1) {
			break;
		}

		var strlen = text.length;

		var inquote = '';
		var found = false;
		var tagnameend = false;
		var optionend = 0;
		var t_char = '';

		for(optionend = tagbegin; optionend <= strlen; optionend++) {
			t_char = text.charAt(optionend);
			if((t_char == '"' || t_char == "'") && inquote == '') {
				inquote = t_char;
			} else if((t_char == '"' || t_char == "'") && inquote == t_char) {
				inquote = '';
			} else if(t_char == '>' && !inquote) {
				found = true;
				break;
			} else if((t_char == '=' || t_char == ' ') && !tagnameend) {
				tagnameend = optionend;
			}
		}

		if(!found) {
			break;
		}
		if(!tagnameend) {
			tagnameend = optionend;
		}

		var offset = optionend - (tagbegin + open_tag_len);
		var tagoptions = text.substr(tagbegin + open_tag_len, offset);
		var acttagname = textlower.substr(tagbegin * 1 + 1, tagnameend - tagbegin - 1);

		if(acttagname != tagname) {
			beginsearchpos = optionend;
			continue;
		}

		var tagend = textlower.indexOf(close_tag, optionend);
		if(tagend == -1) {
			break;
		}

		var nestedopenpos = textlower.indexOf(open_tag, optionend);
		while(nestedopenpos != -1 && tagend != -1) {
			if(nestedopenpos > tagend) {
				break;
			}
			tagend = textlower.indexOf(close_tag, tagend + close_tag_len);
			nestedopenpos = textlower.indexOf(open_tag, nestedopenpos + open_tag_len);
		}

		if(tagend == -1) {
			beginsearchpos = optionend;
			continue;
		}

		var localbegin = optionend + 1;
		var localtext = eval(dofunction)(tagoptions, text.substr(localbegin, tagend - localbegin), tagname, extraargs);

		text = text.substring(0, tagbegin) + localtext + text.substring(tagend + close_tag_len);

		beginsearchpos = tagbegin + localtext.length;

	} while(tagbegin != -1);

	return text;
}

function replyfloor_simpletag(options, text, tagname, parseto) {
	if(trim(text) == '') {
		return '';
	}
	text = replyfloor_recursion(tagname, text, 'replyfloor_simpletag', parseto);
	return '[' + parseto + ']' + text + '[/' + parseto + ']';
}

function replyfloor_smileycode(smileyid) {
	if(typeof smilies_type != 'object') return;
	for(var typeid in smilies_array) {
		for(var page in smilies_array[typeid]) {
			for(var i in smilies_array[typeid][page]) {
				if(smilies_array[typeid][page][i][0] == smileyid) {
					return smilies_array[typeid][page][i][1];
					break;
				}
			}
		}
	}
}
