'use strict';
// Reads Battlegrounds leaderboard player names from Hearthstone's Mono runtime via
// the exported Mono C API (name-based traversal, no hardcoded offsets). Streams the
// current set of visible names to the host every 2s.

const MONO = 'libmonobdwgc-2.0.dylib';
const monoModule = Process.getModuleByName(MONO);

function exp(name) {
    let p = null;
    try { p = monoModule.findExportByName(name); } catch (e) {}
    if (!p) { try { p = Module.getGlobalExportByName(name); } catch (e) {} }
    if (!p) throw new Error('missing mono export: ' + name);
    return p;
}

const mono_get_root_domain        = new NativeFunction(exp('mono_get_root_domain'), 'pointer', []);
const mono_thread_attach          = new NativeFunction(exp('mono_thread_attach'), 'pointer', ['pointer']);
const mono_assembly_foreach       = new NativeFunction(exp('mono_assembly_foreach'), 'void', ['pointer', 'pointer']);
const mono_assembly_get_image     = new NativeFunction(exp('mono_assembly_get_image'), 'pointer', ['pointer']);
const mono_image_get_name         = new NativeFunction(exp('mono_image_get_name'), 'pointer', ['pointer']);
const mono_class_from_name        = new NativeFunction(exp('mono_class_from_name'), 'pointer', ['pointer', 'pointer', 'pointer']);
const mono_class_get_field_from_name = new NativeFunction(exp('mono_class_get_field_from_name'), 'pointer', ['pointer', 'pointer']);
const mono_class_vtable           = new NativeFunction(exp('mono_class_vtable'), 'pointer', ['pointer', 'pointer']);
const mono_field_static_get_value = new NativeFunction(exp('mono_field_static_get_value'), 'void', ['pointer', 'pointer', 'pointer']);
const mono_field_get_value        = new NativeFunction(exp('mono_field_get_value'), 'void', ['pointer', 'pointer', 'pointer']);
const mono_object_get_class       = new NativeFunction(exp('mono_object_get_class'), 'pointer', ['pointer']);
const mono_class_get_name         = new NativeFunction(exp('mono_class_get_name'), 'pointer', ['pointer']);
const mono_string_chars           = new NativeFunction(exp('mono_string_chars'), 'pointer', ['pointer']);

function classNameOf(obj) {
    if (obj.isNull()) return '';
    try { return mono_class_get_name(mono_object_get_class(obj)).readCString() || ''; }
    catch (e) { return ''; }
}

const domain = mono_get_root_domain();
mono_thread_attach(domain);

function cstr(s) { return Memory.allocUtf8String(s); }

function findImage(asmName) {
    let image = NULL;
    const cb = new NativeCallback(function (assembly) {
        try {
            const img = mono_assembly_get_image(assembly);
            if (mono_image_get_name(img).readCString() === asmName) image = img;
        } catch (e) {}
    }, 'void', ['pointer', 'pointer']);
    mono_assembly_foreach(cb, NULL);
    return image;
}

function getRefField(obj, fieldName) {
    if (obj.isNull()) return NULL;
    const field = mono_class_get_field_from_name(mono_object_get_class(obj), cstr(fieldName));
    if (field.isNull()) return NULL;
    const out = Memory.alloc(Process.pointerSize);
    mono_field_get_value(obj, field, out);
    return out.readPointer();
}

function getIntField(obj, fieldName) {
    if (obj.isNull()) return -1;
    const field = mono_class_get_field_from_name(mono_object_get_class(obj), cstr(fieldName));
    if (field.isNull()) return -1;
    const out = Memory.alloc(4);
    mono_field_get_value(obj, field, out);
    return out.readS32();
}

function monoStringToJs(str) {
    if (str.isNull()) return null;
    const chars = mono_string_chars(str);
    const lenField = mono_class_get_field_from_name(mono_object_get_class(str), cstr('length'));
    let len = 0;
    if (!lenField.isNull()) {
        const out = Memory.alloc(4);
        mono_field_get_value(str, lenField, out);
        len = out.readS32();
    }
    if (len <= 0 || len > 256) return chars.readUtf16String();
    return chars.readUtf16String(len);
}

// C# List<T>: backing array _items, logical count _size; return element object pointers.
function listElements(listObj) {
    const result = [];
    if (listObj.isNull()) return result;
    const items = getRefField(listObj, '_items');
    const size = getIntField(listObj, '_size');
    if (items.isNull() || size <= 0 || size > 64) return result;
    const ELT0 = 32; // MonoArray header on 64-bit
    for (let i = 0; i < size; i++) {
        result.push(items.add(ELT0 + i * Process.pointerSize).readPointer());
    }
    return result;
}

function collect() {
    const names = [];
    const empty = { names: names, mode: 'unknown' };
    const image = findImage('Assembly-CSharp');
    if (image.isNull()) return empty;
    const klass = mono_class_from_name(image, cstr(''), cstr('PlayerLeaderboardManager'));
    if (klass.isNull()) return empty;
    const vtable = mono_class_vtable(domain, klass);
    const sField = mono_class_get_field_from_name(klass, cstr('s_instance'));
    if (sField.isNull()) return empty;
    const sBuf = Memory.alloc(Process.pointerSize);
    mono_field_static_get_value(vtable, sField, sBuf);
    const instance = sBuf.readPointer();
    if (instance.isNull()) return empty;

    const teams = getRefField(instance, 'm_teams');
    let mode = 'unknown';
    for (const team of listElements(teams)) {
        const cn = classNameOf(team);
        if (cn.indexOf('Duo') >= 0) mode = 'duos';
        else if (cn.indexOf('Solo') >= 0 && mode === 'unknown') mode = 'solo';
        const cards = getRefField(team, 'm_playerLeaderboardCards');
        for (const tile of listElements(cards)) {
            const overlay = getRefField(tile, 'm_overlay');
            const heroActor = getRefField(overlay, 'm_heroActor');
            const nameText = getRefField(heroActor, 'm_playerNameText');
            let str = NULL;
            for (const f of ['m_Text', 'm_text', 'text']) {
                str = getRefField(nameText, f);
                if (!str.isNull()) break;
            }
            const nm = monoStringToJs(str);
            if (nm && nm.length > 0) names.push(nm);
        }
    }
    return { names: names, mode: mode };
}

function tick() {
    try {
        const r = collect();
        send({ type: 'state', names: r.names, mode: r.mode });
    } catch (e) { send({ type: 'error', error: '' + e }); }
}

tick();
setInterval(tick, 2000);
