.pragma library
// Sync: keeps your saves the same on every computer signed in to the same
// account on your sync server (server/optcg_sync.py).
//
// The app keeps working on its local files. A sync round compares each one
// with the copy last synced ("base", in sync/) and the server's version:
//   only the local file changed   -> upload it (based on the version we have)
//   only the server's changed      -> download it
//   both                           -> three-way merge, then upload the result
// An upload based on an old version is refused by the server (409), so a
// device never overwrites what another one did; it merges and tries again.
//
// Merging: the collection adds up what each side pulled or sold since the
// base; progress adds up berries, packs, stats... and takes the later streak,
// the union of wanted posters, the best completion and so on; a box-mode
// case is one device's (this one's) at a time.
//
// Files in <dataDir>/sync/: account.json (server, username, device token),
// state.json (synced versions, last result), base-<doc>.json.
// The desktop companion syncs every few seconds; the pack opener does it
// itself only while the companion isn't running.

var INTERVAL = 5000;

// ---- files ----------------------------------------------------------------------------

function dir(dataDir) { return dataDir + "/sync"; }

function readJson(host, path, fallback) {
    try { return JSON.parse(host.readText(path) || "null") || fallback; } catch (e) { return fallback; }
}

function account(host, dataDir) {
    return readJson(host, dir(dataDir) + "/account.json", {});
}

function saveAccount(host, dataDir, acc) {
    host.writeText(dir(dataDir) + "/account.json", JSON.stringify(acc, null, 1));
}

function state(host, dataDir) {
    var s = readJson(host, dir(dataDir) + "/state.json", {});
    if (!s.docs) s.docs = {};
    return s;
}

function saveState(host, dataDir, s) {
    host.writeText(dir(dataDir) + "/state.json", JSON.stringify(s, null, 1));
}

function signedIn(acc) {
    return !!(acc && acc.token && acc.server);
}

// this computer, for the passive-income lock (see Progress.addIncome)
function deviceId(host, dataDir) {
    return account(host, dataDir).deviceId || "";
}

// the documents this app syncs, and where they live
function docNames(sets) {
    return ["collection", "progress"].concat(Object.keys(sets || {}).map(function (id) { return "case-" + id; }));
}

function localPath(dataDir, name) {
    return dataDir + "/" + name + ".json";
}

function basePath(dataDir, name) {
    return dir(dataDir) + "/base-" + name + ".json";
}

function format(name, data) {
    return name === "collection" ? JSON.stringify(data, null, 1) : JSON.stringify(data);   // as the app writes them
}

// ---- merging ----------------------------------------------------------------------------

function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

function isObject(x) {
    return x !== null && typeof x === "object" && !Array.isArray(x);
}

function mergeCollection(b, l, r) {
    var out = Object.assign({}, r, l), cards = {};
    var bc = b.cards || {}, lc = l.cards || {}, rc = r.cards || {};
    var keys = {};
    [bc, lc, rc].forEach(function (m) { Object.keys(m).forEach(function (k) { keys[k] = true; }); });
    Object.keys(keys).forEach(function (k) {
        var count = (rc[k] ? rc[k].count : 0) + (lc[k] ? lc[k].count : 0) - (bc[k] ? bc[k].count : 0);
        if (count <= 0) return;
        var e = Object.assign({}, bc[k] || {}, rc[k] || {}, lc[k] || {});
        var firsts = [lc[k], rc[k]].filter(function (x) { return x && x.first; }).map(function (x) { return x.first; }).sort();
        if (firsts.length) e.first = firsts[0];
        e.count = count;
        // copies by condition (Progress.conditions) add up the same way; any
        // more than the count are trimmed when the app reads them
        var cond = {};
        [bc[k], lc[k], rc[k]].forEach(function (x) { Object.keys((x && x.cond) || {}).forEach(function (c) { cond[c] = 0; }); });
        Object.keys(cond).forEach(function (c) {
            var get = function (x) { return (x && x.cond && x.cond[c]) || 0; };
            var n = get(rc[k]) + get(lc[k]) - get(bc[k]);
            if (n > 0) cond[c] = n;
            else delete cond[c];
        });
        if (Object.keys(cond).length) e.cond = cond;
        else delete e.cond;
        cards[k] = e;
    });
    out.cards = cards;
    out.packs = Math.max(0, (r.packs || 0) + (l.packs || 0) - (b.packs || 0));
    // graded slabs: by id; one sold or added on either side stays that way
    var graded = mergeTree(b.graded || {}, l.graded || {}, r.graded || {}, "graded");
    if (graded && Object.keys(graded).length) out.graded = graded;
    else delete out.graded;
    // fakes from card shows: by id, the same way
    var fakes = mergeTree(b.fakes || {}, l.fakes || {}, r.fakes || {}, "graded");
    if (fakes && Object.keys(fakes).length) out.fakes = fakes;
    else delete out.fakes;
    // saved sets (the vault's display cases): by id, the same way
    var sets = mergeTree(b.sets || {}, l.sets || {}, r.sets || {}, "sets");
    if (sets && Object.keys(sets).length) out.sets = sets;
    else delete out.sets;
    return out;
}

function pickLater(field) {
    return function (b, l, r) {
        if (!isObject(l)) return r;
        if (!isObject(r)) return l;
        return (l[field] || 0) >= (r[field] || 0) ? l : r;
    };
}

function max(b, l, r) {
    if (typeof l !== "number") return r;
    if (typeof r !== "number") return l;
    return Math.max(l, r);
}

function preferLocal(b, l, r) {
    return l !== undefined ? l : r;
}

function earliest(b, l, r) {
    if (l === undefined) return r;
    if (r === undefined) return l;
    return l < r ? l : r;
}

function mergeStreak(b, l, r) {
    if (!isObject(l)) return r;
    if (!isObject(r)) return l;
    if (l.day !== r.day) return l.day > r.day ? l : r;
    return l.count >= r.count ? l : r;
}

function mergeIncome(b, l, r) {
    if (!isObject(l)) return r;
    if (!isObject(r)) return l;
    if (l.day !== r.day) return l.day > r.day ? l : r;
    var base = isObject(b) && b.day === l.day ? b.earned || 0 : 0;
    var later = (l.at || 0) >= (r.at || 0) ? l : r;
    return Object.assign({}, later, { earned: Math.max(0, (l.earned || 0) + (r.earned || 0) - base) });
}

// today's card shop purchases: the later day; the same day, both sides' purchases
function mergeShop(b, l, r) {
    if (!isObject(l)) return r;
    if (!isObject(r)) return l;
    if (l.day !== r.day) return l.day > r.day ? l : r;
    return { day: l.day, bought: Object.assign({}, r.bought || {}, l.bought || {}) };
}

// the card show: the later show; the same show, its stock as first dealt, both sides'
// purchases and trades, sales, offers asked for, haggles, checks and questions, in when either walked in, out when either left
function mergeShow(b, l, r) {
    if (!isObject(l)) return r;
    if (!isObject(r)) return l;
    if (l.day !== r.day) return l.day > r.day ? l : r;
    var first = function (x, y) { return x && y ? Math.min(x, y) : x || y || 0; };
    return { day: l.day, entered: first(l.entered, r.entered), left: Math.max(l.left || 0, r.left || 0),
             stock: (l.entered && r.entered ? (l.entered <= r.entered ? l : r) : l.entered ? l : r).stock || l.stock || r.stock,
             bought: Object.assign({}, r.bought || {}, l.bought || {}), haggled: Object.assign({}, r.haggled || {}, l.haggled || {}),
             checked: mergeChecked(l.checked, r.checked), asked: Object.assign({}, r.asked || {}, l.asked || {}),
             sold: Object.assign({}, r.sold || {}, l.sold || {}), offers: Object.assign({}, r.offers || {}, l.offers || {}),
             reports: Object.assign({}, r.reports || {}, l.reports || {}), rep: Math.max(l.rep || 0, r.rep || 0),
             taken: Object.assign({}, r.taken || {}, l.taken || {}), clock: Math.max(l.clock || 0, r.clock || 0),
             news: (l.news || []).length >= (r.news || []).length ? l.news : r.news, early: !!(l.early || r.early), paid: l.paid || r.paid || 0,
             expo: !!(l.expo || r.expo), authed: Object.assign({}, r.authed || {}, l.authed || {}),
             auction: auctionAhead(l.auction, r.auction),
             looks: Math.max(l.looks || 0, r.looks || 0) };
}

// the auction further along: decided beats open beats not open; then the higher bid
function auctionAhead(l, r) {
    if (!isObject(l)) return r || null;
    if (!isObject(r)) return l;
    var rank = function (a) { return (a.state === "won" || a.state === "lost" ? 2 : a.state === "open" ? 1 : 0) * 1e12 + (a.bid || 0); };
    return rank(l) >= rank(r) ? l : r;
}

// what was checked of each listing, on either device
function mergeChecked(l, r) {
    var out = {};
    [r || {}, l || {}].forEach(function (side) {
        Object.keys(side).forEach(function (id) { out[id] = Object.assign(out[id] || {}, side[id]); });
    });
    return out;
}

// this week's event and bounties: the later week; the same week, each bounty's best progress
function mergeWeekly(b, l, r) {
    if (!isObject(l)) return r;
    if (!isObject(r)) return l;
    if (l.week !== r.week) return l.week > r.week ? l : r;
    return Object.assign({}, l, { list: mergeBounties({}, { day: 0, list: l.list }, { day: 0, list: r.list }).list });
}

// this month's season: the later month; the same month, counters add up, goals and rewards combine
function mergeSeason(b, l, r) {
    if (!isObject(l)) return r;
    if (!isObject(r)) return l;
    if (l.id !== r.id) return l.id > r.id ? l : r;
    return mergeTree(isObject(b) && b.id === l.id ? b : {}, l, r, "seasonOf");
}

function mergeBounties(b, l, r) {
    if (!isObject(l)) return r;
    if (!isObject(r)) return l;
    if (l.day !== r.day) return l.day > r.day ? l : r;
    return { day: l.day, list: (l.list || []).map(function (x, i) {
        var y = (r.list || [])[i];
        if (!y || y.kind !== x.kind) return x;
        return Object.assign({}, x, { progress: Math.max(x.progress, y.progress), done: x.done || y.done });
    }) };
}

// progress.json: special cases by path ("*" matches any key); everything
// else merges by key, numbers adding up both sides' changes
var PROGRESS_RULES = [
    ["version", max], ["freePackClock", max],
    ["streak", mergeStreak], ["income", mergeIncome], ["focus", pickLater("startedAt")], ["bounties", mergeBounties],
    ["achievements.*", earliest], ["graded.*", slab], ["grading.*", slab], ["sealed.*", slab],
    ["sets.*", slab], ["collections.*", slab],
    ["stats.bestCompletion", max], ["stats.backfilled", max], ["stats.value", preferLocal], ["stats.setBonus", preferLocal],
    ["stats.bySet.*.completion", max], ["stats.bySet.*.groups.*", max],
    ["stats.bySet.*.present", preferLocal], ["stats.bySet.*.value", preferLocal],
    // the Port
    ["ship.level", max], ["crew.*", earliest], ["shop", mergeShop], ["show", mergeShow],
    ["showBinder", pickLater("at")], ["showNotes", pickLater("at")], ["showTutorial.*", earliest],
    ["showRegulars.*.deals", max], ["showRegulars.*.last", max], ["showRep", pickLater("at")],
    ["weekly", mergeWeekly], ["season", mergeSeason], ["seasonOf.done.*", earliest], ["seasonOf.tiers.*", earliest],
    ["titles.*", preferLocal], ["seasons.*", preferLocal],
    ["cosmetics.owned.*", earliest], ["cosmetics.backdrop", preferLocal], ["cosmetics.slab", preferLocal]
];

// a graded slab is one thing: either side's copy, not a sum of its numbers
function slab(b, l, r) {
    if (l === undefined || r === undefined) return same(l, b) ? r : same(r, b) ? l : (l || r);
    return l;
}

function ruleFor(path) {
    for (var i = 0; i < PROGRESS_RULES.length; i++) {
        var a = PROGRESS_RULES[i][0].split("."), p = path.split(".");
        if (a.length === p.length && a.every(function (x, j) { return x === "*" || x === p[j]; })) return PROGRESS_RULES[i][1];
    }
    return null;
}

function mergeTree(b, l, r, path) {
    var rule = path ? ruleFor(path) : null;
    if (rule) return rule(b, l, r);
    if (same(l, b)) return r;
    if (same(r, b)) return l;
    if (same(l, r)) return l;
    if (typeof l === "number" && typeof r === "number")
        return Math.max(0, r + l - (typeof b === "number" ? b : 0));
    if (isObject(l) && isObject(r)) {
        var out = {}, keys = {}, bb = isObject(b) ? b : {};
        Object.keys(l).concat(Object.keys(r)).forEach(function (k) { keys[k] = true; });
        Object.keys(keys).forEach(function (k) {
            var v = mergeTree(bb[k], l[k], r[k], path ? path + "." + k : k);
            if (v !== undefined) out[k] = v;
        });
        return out;
    }
    return l !== undefined ? l : r;   // a real conflict: this device wins
}

// three-way merge of a document; base may be {} (nothing in common yet)
function merge(name, base, local, remote) {
    base = base || {};
    if (!remote) return local;
    if (!local) return remote;
    if (name === "collection") return mergeCollection(base, local, remote);
    if (name === "progress") return mergeTree(base, local, remote, "");
    return local;   // a box-mode case: this device's
}

// ---- the server ----------------------------------------------------------------------------

// https only, except for a server on this computer
function serverProblem(url) {
    if (!/^https?:\/\/[^\s\/?#]+/.test(url)) return "The server address should look like https://sync.example.com";
    if (/^http:/.test(url) && !/^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(\/|$)/.test(url))
        return "Use https:// so your password isn't sent in the clear.";
    return "";
}

function cleanServer(url) {
    return url.trim().replace(/\/+$/, "");
}

// cb(status, json); status 0: couldn't reach the server
function request(acc, method, path, body, cb) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        var json = {};
        try { json = JSON.parse(xhr.responseText) || {}; } catch (e) {}
        cb(xhr.status, json);
    };
    xhr.open(method, acc.server + path);
    xhr.setRequestHeader("Content-Type", "application/json");
    if (acc.token) xhr.setRequestHeader("Authorization", "Bearer " + acc.token);
    xhr.send(body !== undefined ? JSON.stringify(body) : (method === "POST" || method === "PUT" ? "{}" : ""));
}

// the server's message for a failed request
function errorText(status, json) {
    if (status === 0) return "Couldn't reach the sync server.";
    var d = json && json.detail;
    if (typeof d === "string") return d;
    if (Array.isArray(d) && d.length && d[0].msg) return String(d[0].msg).replace(/^Value error, /, "");
    return "The sync server said " + status + ".";
}

function randomId() {
    var s = "";
    for (var i = 0; i < 4; i++) s += Math.floor(Math.random() * 0x100000000).toString(16);
    return s;
}

// sign in or create an account: cb(error or "", { hasData }) -- hasData: the
// account already holds saves; syncing waits (account.pending) until
// finishLink() says whether to use the account's saves or combine them
function signIn(host, dataDir, form, create, cb) {
    var server = cleanServer(form.server || "");
    var problem = serverProblem(server);
    if (problem) { cb(problem); return; }
    var acc = { server: server };
    var body = { username: form.username, password: form.password, device: form.device };
    if (create) body.invite = form.invite || "";
    request(acc, "POST", create ? "/v1/accounts" : "/v1/sessions", body, function (status, json) {
        if (status !== 201) { cb(errorText(status, json)); return; }
        acc = { server: server, username: json.username, token: json.token, device: form.device, deviceId: randomId() };
        request(acc, "GET", "/v1/docs", undefined, function (s2, docs) {
            // start fresh: no bases, so the first round merges this computer's saves with the account's
            var hasData = s2 === 200 && Object.keys(docs.docs || {}).length > 0;
            if (hasData) acc.pending = true;
            saveAccount(host, dataDir, acc);
            resetSync(host, dataDir);
            cb("", { hasData: hasData });
        });
    });
}

function resetSync(host, dataDir) {
    var s = state(host, dataDir);
    Object.keys(s.docs).forEach(function (n) { host.writeText(basePath(dataDir, n), ""); });
    saveState(host, dataDir, { docs: {} });
}

// replace this computer's saves with the account's (a copy of them goes to sync/backup-*)
function useAccountData(host, dataDir, sets, cb) {
    var acc = account(host, dataDir), stamp = new Date().toISOString().replace(/[:.]/g, "-");
    request(acc, "GET", "/v1/docs", undefined, function (status, json) {
        if (status !== 200) { cb(errorText(status, json)); return; }
        // only names the server itself allows: they become file names here
        var names = Object.keys(json.docs || {}).filter(function (n) {
            return /^(collection|progress|case-[A-Za-z0-9-]{1,24})$/.test(n);
        }), s = state(host, dataDir);
        var next = function (i) {
            if (i >= names.length) { saveState(host, dataDir, s); cb(""); return; }
            request(acc, "GET", "/v1/docs/" + names[i], undefined, function (st, doc) {
                if (st !== 200) { cb(errorText(st, doc)); return; }
                var path = localPath(dataDir, names[i]), old = host.readText(path), text = format(names[i], doc.data);
                if (old) host.writeText(dir(dataDir) + "/backup-" + stamp + "-" + names[i] + ".json", old);
                host.writeText(path, text);
                host.writeText(basePath(dataDir, names[i]), text);
                s.docs[names[i]] = doc.version;
                next(i + 1);
            });
        };
        next(0);
    });
}

// after signing in to an account that has saves: useAccount -> replace this
// computer's with them, else combine both (the first sync round merges them)
function finishLink(host, dataDir, sets, useAccount, cb) {
    var go = function (err) {
        if (!err) {
            var acc = account(host, dataDir);
            delete acc.pending;
            saveAccount(host, dataDir, acc);
        }
        cb(err || "");
    };
    if (useAccount) useAccountData(host, dataDir, sets, go);
    else go("");
}

function signOut(host, dataDir, cb) {
    var acc = account(host, dataDir);
    var done = function () {
        saveAccount(host, dataDir, { server: acc.server || "", username: acc.username || "", device: acc.device || "" });
        resetSync(host, dataDir);
        if (cb) cb();
    };
    if (signedIn(acc)) request(acc, "DELETE", "/v1/sessions/current", undefined, done);
    else done();
}

// signed-in calls for the account screen: cb(error or "", json)
function call(host, dataDir, method, path, body, cb) {
    var acc = account(host, dataDir);
    request(acc, method, path, body, function (status, json) {
        if (status === 401 && path.indexOf("/v1/account/") !== 0) signedOutByServer(host, dataDir);
        cb(status >= 200 && status < 300 ? "" : errorText(status, json), json);
    });
}

function signedOutByServer(host, dataDir) {
    var acc = account(host, dataDir);
    saveAccount(host, dataDir, { server: acc.server || "", username: acc.username || "", device: acc.device || "" });
    resetSync(host, dataDir);
    var s = state(host, dataDir);
    s.error = "Signed out by the server (password changed or this computer removed). Sign in again.";
    saveState(host, dataDir, s);
}

// ---- a sync round ---------------------------------------------------------------------------

var busySince = 0;

// one round over every document; who: "companion" | "opener" (recorded, so
// the opener knows the companion is on it). done(changed: names written locally)
function syncOnce(host, dataDir, sets, who, done) {
    var acc = account(host, dataDir);
    if (!signedIn(acc) || acc.pending) { if (done) done([]); return; }
    if (busySince && Date.now() - busySince < 60000) return;
    busySince = Date.now();
    var s = state(host, dataDir), changed = [], error = "";
    var finish = function () {
        busySince = 0;
        var now = state(host, dataDir);
        now.docs = s.docs;
        now.lastSync = error ? now.lastSync || 0 : Date.now();
        now.error = error;
        now.by = who;
        now.at = Date.now();
        if (signedIn(account(host, dataDir))) saveState(host, dataDir, now);
        if (done) done(changed);
    };
    request(acc, "GET", "/v1/docs", undefined, function (status, json) {
        if (status === 401) { busySince = 0; signedOutByServer(host, dataDir); if (done) done([]); return; }
        if (status !== 200) { error = errorText(status, json); finish(); return; }
        var server = json.docs || {}, names = docNames(sets).filter(function (n) {
            return server[n] || host.readText(localPath(dataDir, n)) !== "";
        });
        var next = function (i) {
            if (i >= names.length) { finish(); return; }
            syncDoc(host, dataDir, acc, s, names[i], server[names[i]] ? server[names[i]].version : 0, changed, function (err) {
                if (err) error = err;
                next(i + 1);
            });
        };
        next(0);
    });
}

function syncDoc(host, dataDir, acc, s, name, serverVersion, changed, cb) {
    var path = localPath(dataDir, name), bpath = basePath(dataDir, name);
    var local = host.readText(path), base = host.readText(bpath), have = s.docs[name] || 0;
    var parse = function (text) { try { return text ? JSON.parse(text) : null; } catch (e) { return null; } };

    // write what we got, unless the app changed the file meanwhile (then next round merges it)
    function writeLocal(data) {
        if (host.readText(path) !== local) return false;
        var text = format(name, data);
        if (text !== local) {
            host.writeText(path, text);
            changed.push(name);
        }
        local = text;
        return true;
    }
    function upload(data, baseVersion) {
        request(acc, "PUT", "/v1/docs/" + name, { base: baseVersion, data: data }, function (status, json) {
            if (status === 200) {
                host.writeText(bpath, format(name, data));
                s.docs[name] = json.version;
                cb("");
            } else if (status === 409) {
                resolve(json.data, json.version);
            } else {
                cb(errorText(status, json));
            }
        });
    }
    // the server has something newer than our base: merge it in and upload
    function resolve(remote, version) {
        var merged = merge(name, parse(base) || {}, parse(local), remote);
        if (!writeLocal(merged)) { cb(""); return; }
        if (same(merged, remote)) {
            host.writeText(bpath, local);
            s.docs[name] = version;
            cb("");
        } else {
            base = format(name, remote);
            upload(merged, version);
        }
    }

    var localChanged = local !== "" && local !== base;   // a missing file is restored from the server
    if (!localChanged && serverVersion === have && (local || !serverVersion)) { cb(""); return; }
    if (localChanged && serverVersion === have) {
        var data = parse(local);
        if (!data) { cb(""); return; }   // half-written; next round
        upload(data, have);
        return;
    }
    if (serverVersion === 0) {   // not on the server (any more): upload ours
        if (parse(local)) upload(parse(local), 0);
        else cb("");
        return;
    }
    request(acc, "GET", "/v1/docs/" + name, undefined, function (status, json) {
        if (status !== 200) { cb(errorText(status, json)); return; }
        if (!localChanged) {
            if (writeLocal(json.data)) {
                host.writeText(bpath, local);
                s.docs[name] = json.version;
            }
            cb("");
        } else {
            resolve(json.data, json.version);
        }
    });
}

// is the companion syncing (so the opener needn't)?
function companionSyncing(host, dataDir) {
    var s = state(host, dataDir);
    return s.by === "companion" && Date.now() - (s.at || 0) < 4 * INTERVAL;
}

// "synced 12s ago" / the last error
function statusText(host, dataDir) {
    var acc = account(host, dataDir), s = state(host, dataDir);
    if (!signedIn(acc)) return s.error || "not signed in";
    if (s.error) return s.error;
    if (!s.lastSync) return "syncing...";
    var secs = Math.round((Date.now() - s.lastSync) / 1000);
    return "synced " + (secs < 60 ? secs + "s" : Math.round(secs / 60) + " min") + " ago";
}
