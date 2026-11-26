"""在 CI 里由 flutter create 生成 android/ 之后运行：补权限、minSdk、明文 HTTP"""
import pathlib, re

m = pathlib.Path("android/app/src/main/AndroidManifest.xml")
x = m.read_text(encoding="utf-8")
perms = [
    "android.permission.INTERNET",
    "android.permission.WAKE_LOCK",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.MANAGE_EXTERNAL_STORAGE",
]
add = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in x)
x = re.sub(r"(<manifest[^>]*>\n?)", r"\1" + add, x, count=1)
if "usesCleartextTraffic" not in x:
    x = x.replace("<application", '<application\n        android:usesCleartextTraffic="true"\n        android:requestLegacyExternalStorage="true"', 1)
x = re.sub(r'android:label="[^"]*"', 'android:label="PexDL"', x, count=1)
m.write_text(x, encoding="utf-8")

for name in ["android/app/build.gradle.kts", "android/app/build.gradle"]:
    g = pathlib.Path(name)
    if not g.exists():
        continue
    t = g.read_text(encoding="utf-8")
    t = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", lambda mm: ("minSdk = 24" if name.endswith("kts") else "minSdkVersion 24"), t)
    g.write_text(t, encoding="utf-8")
    print("patched", name)
print(x)
