/*
    Real-time subtitle translate for PotPlayer using Volcengine (ByteDance) TranslateText API
    - No external program
    - AngelScript only (uses PotPlayer builtin APIs)
    - HMAC-SHA256 signing implemented in script
    - First request fetches server Date to build X-Date
*/

// ---------------- UI / Metadata ----------------
string GetTitle()       { return "{$CP949=Volcengine 번역$}{$CP950=火山引擎 翻譯$}{$CP0=Volcengine translate$}"; }
string GetVersion()     { return "2"; }
string GetDesc()        { return "https://www.volcengine.com/product/machine-translation"; }
string GetLoginTitle()  { return "Input Volcengine AK/SK"; }
string GetLoginDesc()   { return "Enter AccessKey ID and SecretAccessKey (kept in memory only)"; }
string GetUserText()    { return "AccessKey ID:"; }
string GetPasswordText(){ return "SecretAccessKey:"; }

// ---------------- Globals ----------------
string AK = "";
string SK = "";
string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PotPlayer-Volcengine/1.0";
string ENDPOINT_HOST = "open.volcengineapi.com";
string ENDPOINT_URL  = "https://open.volcengineapi.com/?Action=TranslateText&Version=2020-06-01";
string SERVICE = "translate";
string REGION  = "cn-north-1";

// cache Date
string CACHED_X_DATE = "";      // e.g. 20250115T121314Z
string CACHED_YYYYMMDD = "";    // e.g. 20250115
uint   CACHED_DATE_TICK = 0;    // HostGetTickCount() when fetched

// ---------------- Login / Logout ----------------
string ServerLogin(string User, string Pass)
{
    AK = User.Trim();
    SK = Pass.Trim();
    if (AK.empty() || SK.empty()) return "fail";
    // lazy fetch server date on first translate
    return "200 ok";
}
void ServerLogout() { AK = ""; SK = ""; CACHED_X_DATE=""; CACHED_YYYYMMDD=""; CACHED_DATE_TICK=0; }

// ---------------- Language Tables ----------------
array<string> SrcLangTable = 
{
    "ar","bg","zh","cs","da","nl","en","et","fi","fr","de","el","hu","id","it","ja","ko","lv","lt","nb","pl","pt","ro","ru","sk","sl","es","sv","tr","uk"
};
array<string> DstLangTable = 
{
    "ar","bg","zh","cs","da","nl","en","et","fi","fr","de","el","hu","id","it","ja","ko","lv","lt","nb","pl","pt","ro","ru","sk","sl","es","sv","tr","uk"
};
array<string> GetSrcLangs(){ array<string> ret = SrcLangTable; ret.insertAt(0,""); return ret; }
array<string> GetDstLangs(){ array<string> ret = DstLangTable; return ret; }

// ---------------- Utilities: bytes/xor/hex/base ----------------
string HexLower(const string &in bin)
{
    // PotPlayer strings are byte containers; build hex
    string hex = "";
    for (uint i=0;i<bin.length();i++){
        uint8 c = uint8(bin[i]);
        const string H = "0123456789abcdef";
        hex += H[c>>4];
        hex += H[c&15];
    }
    return hex;
}
string FromHex(const string &in hex)
{
    string out="";
    for (uint i=0;i+1<hex.length(); i+=2){
        int hi = ParseHex(hex[i]); int lo = ParseHex(hex[i+1]);
        out += uint8((hi<<4)|lo);
    }
    return out;
}
int ParseHex(uint8 ch){
    if (ch>='0' && ch<='9') return ch-'0';
    if (ch>='a' && ch<='f') return 10 + (ch-'a');
    if (ch>='A' && ch<='F') return 10 + (ch-'A');
    return 0;
}
string XORPad(string key, uint8 pad, int block=64)
{
    if (int(key.length())>block) {
        // SHA256 of key when longer than block (per HMAC)
        string kh = HostHashSHA256(key); // hex
        key = FromHex(kh);
    }
    // right-pad with zeros to block length
    if (int(key.length())<block) key += string(block - int(key.length()), uint8(0));
    string out="";
    for (int i=0;i<block;i++){
        out += uint8(uint8(key[i]) ^ pad);
    }
    return out;
}

// ---------------- HMAC-SHA256 (returns raw bytes) ----------------
string HMAC_SHA256(const string &in key, const string &in msg)
{
    string kipad = XORPad(key, 0x36, 64);
    string kopad = XORPad(key, 0x5c, 64);
    // inner = sha256(kipad || msg)
    string inner_hex = HostHashSHA256(kipad + msg);        // returns hex
    string inner_raw = FromHex(inner_hex);
    // outer = sha256(kopad || inner)
    string outer_hex = HostHashSHA256(kopad + inner_raw);
    return FromHex(outer_hex);
}

// ---------------- Volc SigV4-like Key Derivation ----------------
string DeriveSigningKey(const string &in sk, const string &in yyyymmdd, const string &in region, const string &in service)
{
    string kDate    = HMAC_SHA256(sk, yyyymmdd);
    string kRegion  = HMAC_SHA256(kDate, region);
    string kService = HMAC_SHA256(kRegion, service);
    string kSign    = HMAC_SHA256(kService, "request");
    return kSign; // raw
}

// ---------------- Server Date fetch (once per ~5 min) ----------------
bool EnsureServerDate()
{
    uint now = HostGetTickCount();
    if (!CACHED_X_DATE.empty() && (now - CACHED_DATE_TICK) < 300000) return true; // 5 minutes

    // GET endpoint root to read "Date:" header (UTC)
    uintptr h = HostOpenHTTP("https://" + ENDPOINT_HOST + "/", UserAgent, "", "", true);
    if (h == 0) return false;
    string hdr = HostGetHeaderHTTP(h);
    HostCloseHTTP(h);

    // Parse Date header: e.g. "Date: Tue, 15 Aug 2025 12:13:14 GMT"
    // Regex-friendly：抓整行
    array<dictionary> caps;
    bool ok = HostRegExpParse(hdr, "Date:\\s*([A-Za-z]{3},\\s*\\d{2}\\s*[A-Za-z]{3}\\s*\\d{4}\\s*\\d{2}:\\d{2}:\\d{2}\\s*GMT)", caps);
    if (!ok || caps.size()==0) return false;
    string d = string(caps[0]["first"]);

    // Month map
    array<string> M = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
    // Parse pieces
    // Format: "Tue, 15 Aug 2025 12:13:14 GMT"
    array<dictionary> p;
    bool ok2 = HostRegExpParse(d, "^[A-Za-z]{3},\\s*(\\d{2})\\s*([A-Za-z]{3})\\s*(\\d{4})\\s*(\\d{2}):(\\d{2}):(\\d{2})\\s*GMT$", p);
    if (!ok2 || p.size()<6) return false;

    string DD = string(p[0]["first"]);
    string MonStr = string(p[1]["first"]);
    string YYYY = string(p[2]["first"]);
    string HH = string(p[3]["first"]);
    string MM = string(p[4]["first"]);
    string SS = string(p[5]["first"]);

    int monIdx = 0; for (int i=0;i<int(M.length());i++){ if (MonStr==M[i]) { monIdx=i+1; break; } }
    string MON = (monIdx<10? "0"+string(monIdx): string(monIdx));

    CACHED_YYYYMMDD = YYYY + MON + DD;
    CACHED_X_DATE   = CACHED_YYYYMMDD + "T" + HH + MM + SS + "Z";
    CACHED_DATE_TICK = now;
    return true;
}

// ---------------- Canonical / Authorization ----------------
string SHA256_HEX(const string &in s){ return HostHashSHA256(s); } // hex

string BuildAuthorization(const string &in x_date, const string &in yyyymmdd,
                          const string &in content_type, const string &in host,
                          const string &in canonical_query, const string &in body_raw_hex)
{
    // Canonical request
    string canonical_uri = "/";
    string canonical_headers =
        "content-type:" + content_type + "\n" +
        "host:" + host + "\n" +
        "x-content-sha256:" + body_raw_hex + "\n" +
        "x-date:" + x_date + "\n";
    string signed_headers = "content-type;host;x-content-sha256;x-date";

    string canonical_request = 
        "POST\n" + 
        canonical_uri + "\n" +
        canonical_query + "\n" +
        canonical_headers + "\n" +
        signed_headers + "\n" +
        body_raw_hex;

    string algorithm = "HMAC-SHA256";
    string credential_scope = yyyymmdd + "/" + REGION + "/" + SERVICE + "/request";

    string string_to_sign =
        algorithm + "\n" +
        x_date + "\n" +
        credential_scope + "\n" +
        SHA256_HEX(canonical_request); // hex

    string kSign = DeriveSigningKey(SK, yyyymmdd, REGION, SERVICE);
    // signature = hex(hmac(kSign, string_to_sign))
    string sig_raw = HMAC_SHA256(kSign, string_to_sign);
    string signature = HexLower(sig_raw);

    string authorization =
        algorithm + " Credential=" + AK + "/" + credential_scope +
        ", SignedHeaders=" + signed_headers +
        ", Signature=" + signature;

    return authorization;
}

// ---------------- JSON Parse (Volc response) ----------------
string JsonParse(string json)
{
    JsonReader Reader; JsonValue Root; string ret = "";
    if (Reader.parse(json, Root) && Root.isObject())
    {
        JsonValue tl = Root["TranslationList"];
        if (tl.isArray()){
            for (int i=0;i<tl.size();i++){
                JsonValue it = tl[i];
                if (it.isObject()){
                    JsonValue T = it["Translation"];
                    if (T.isString()){
                        if (!ret.empty()) ret += "\n";
                        ret += T.asString();
                    }
                }
            }
        }
        // 错误信息透传（可选）
        if (ret.empty()){
            JsonValue meta = Root["ResponseMetadata"];
            if (meta.isObject()){
                JsonValue err = meta["Error"];
                if (err.isObject()){
                    JsonValue msg = err["Message"];
                    if (msg.isString()){
                        ret = "[Volc Error] " + msg.asString();
                    }
                }
            }
        }
    }
    return ret;
}

// ---------------- Lang normalize（把 en-gb / pt-br 等收敛） ----------------
string NormalizeSrc(const string &in s){
    if (s.empty()) return ""; // auto
    string t = s; t.MakeLower();
    if (t.find("en-") == 0) return "en";
    if (t == "pt-pt" || t == "pt-br" || t == "pt") return "pt";
    if (t == "zh-cn" || t == "zh-hans" || t == "zh-hant" || t == "zh-tw" || t=="zh") return "zh";
    return t;
}
string NormalizeDst(const string &in s){
    string t = s; t.MakeLower();
    if (t.find("en-") == 0) return "en";
    if (t == "pt-pt" || t == "pt-br" || t == "pt") return "pt";
    if (t == "zh-cn" || t == "zh-hans" || t == "zh-hant" || t == "zh-tw" || t=="zh") return "zh";
    return t;
}

// ---------------- Core Translate ----------------
string Translate(string Text, string &in SrcLang, string &in DstLang)
{
    if (AK.empty() || SK.empty()) return "";

    // 1) ensure server date
    if (!EnsureServerDate()) return "";

    // 2) build body JSON
    string src = NormalizeSrc(SrcLang);
    string dst = NormalizeDst(DstLang);
    if (dst.empty()) dst = "zh";

    // JSON 手拼，TextList 只发一段；你要批量合并，自己改这里拼数组
    // 为了安全，转义 \ 和 " 以及换行
    string tx = Text;
    tx.replace("\\","\\\\"); tx.replace("\"","\\\"");
    tx.replace("\r","\\n");  tx.replace("\n","\\n");

    string body = "{";
    if (!src.empty()) body += "\"SourceLanguage\":\"" + src + "\",";
    body += "\"TargetLanguage\":\"" + dst + "\",";
    body += "\"TextList\":[\"" + tx + "\"]}";

    // 3) hashed payload
    string body_sha256_hex = HostHashSHA256(body); // hex

    // 4) canonical query
    string canonical_query = "Action=TranslateText&Version=2020-06-01";

    // 5) authorization
    string auth = BuildAuthorization(CACHED_X_DATE, CACHED_YYYYMMDD,
                                    "application/json", ENDPOINT_HOST,
                                    canonical_query, body_sha256_hex);

    // 6) HTTP headers
    string header = 
        "Content-Type: application/json\r\n"
        "Host: " + ENDPOINT_HOST + "\r\n"
        "X-Date: " + CACHED_X_DATE + "\r\n"
        "X-Content-Sha256: " + body_sha256_hex + "\r\n"
        "Authorization: " + auth + "\r\n";

    // 7) POST
    string resp = HostUrlGetString(ENDPOINT_URL, UserAgent, header, body, true);
    string ret = JsonParse(resp);
    if (ret.length() > 0)
    {
        string UNICODE_RLE = "\u202B";
        string dlow = dst; dlow.MakeLower();
        if (dlow=="fa" || dlow=="ar" || dlow=="he") ret = UNICODE_RLE + ret;
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return ret;
    }
    return "";
}
