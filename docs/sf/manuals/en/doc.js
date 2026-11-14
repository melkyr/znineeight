function swap(imgId) {
	var im = imgId, s, p;
	if (typeof im == "string") { im = document.images[im]; }
	if (!im) { return; }
	s = im.src;
	p = s.indexOf("-over.gif");
	if (p > -1) { im.src = s.substring(0, p) + ".gif"; }
	else { im.src = s.substring(0, s.lastIndexOf(".")) + "-over.gif"; }
}

function tocToggle() {
	var t = null, l;
	if (document.getElementById) { t = document.getElementById("toc"); }
	else if (document.all) { t = document.all["toc"]; }
	if (t && t.style) {
		t.style.display = (t.style.display == "none") ? "" : "none";
	}
	else if (document.layers && document.layers["toc"]) {
		l = document.layers["toc"];
		l.visibility = (l.visibility == "hide") ? "show" : "hide";
	}
}

function doSearch() {
	var box = null, out = null, q, i, e, h = "";
	if (document.getElementById) {
		box = document.getElementById("q");
		out = document.getElementById("results");
	}
	else if (document.all) {
		box = document.all["q"];
		out = document.all["results"];
	}
	if (!box || !out || typeof out.innerHTML == "undefined" || typeof z98SearchData == "undefined") { return false; }
	q = box.value.toLowerCase();
	if (q == "") { out.innerHTML = ""; return false; }
	for (i = 0; i < z98SearchData.length; i++) {
		e = z98SearchData[i];
		if ((e.title + " " + e.keywords).toLowerCase().indexOf(q) > -1) {
			h += '<p><a href="' + e.file + '">' + e.title + "</a></p>";
		}
	}
	out.innerHTML = h ? h : "<p>No matches.</p>";
	return false;
}

function preload() {
	var n = ["home", "prev", "next", "up", "index", "search"], i, im;
	for (i = 0; i < n.length; i++) {
		im = new Image();
		im.src = "gfx/btn-" + n[i] + "-over.gif";
	}
}
