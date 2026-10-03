# signing/ (ignored by git)

Your personal files for signing watch apps live here. Apart from this README and
`signing.env.example`, nothing in this folder is committed (`.gitignore`).

```
signing/
  signing.env              signing settings (copy from signing.env.example)
  mykey.p12                your private key (keystore)
  password.txt             keystore password
  mykey-debug.cer          debug certificate downloaded from AppGallery Connect
  profiles/
    com.yourname.huasideload.sample.p7b    one debug profile per watch app, named after its package
```

How to get them: main README > "Huawei developer account and signing".
