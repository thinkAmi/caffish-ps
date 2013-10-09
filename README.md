caffish-ps
========

キーサインパーティの時に使用するcaffっぽいものをWindows + PowerShellで実装したものです。
実際にはGpg4winを叩いて暗号化などを行い、.NETのクラスライブラリを使ってメールを送信します。

なお、必要に応じて、メール送信はThunderbirdに行わせることも可能です。


機能
----------
キーサインパーティ後に行う、以下の作業を自動化します。  


1. 「gpg --keyserver <キーサーバ> --recv-key <相手の公開鍵ID>」でキーサーバより相手の公開鍵を取得し、自分の公開鍵の鍵束に入れる
2. 「gpg --fingerprint <相手の公開鍵ID>」で表示する
3. 「gpg --sign-key <相手の公開鍵ID>」で相手の公開鍵に署名する
4. 「gpg --export --armor --output <ローカルの出力先> <相手の公開鍵ID>」で署名した公開鍵をエクスポートする
5. エクスポートした公開鍵をメールに添付し、メールを暗号化して相手へ送信する

利用者は、フィンガープリントの確認と「y」キーで処理を続行してメールを送信します。
　  
　  
#### 実装していない機能
caffっぽくすることを考えたため、以下の機能はあえて実装していません。

* サーバから取得した公開鍵に対し、信頼度の変更をすること (gpg --edit-key <ID> のあとの、trust)
* PowerShellでメールを送信する際、メールに自分の秘密鍵による署名を付けること


また、実装的にはPowerShellによるGpg4winの単なるラッパーであることから、以下の機能が実現できませんでした。

* キーサーバから公開鍵を取得する際、自分の公開鍵の鍵束に入れずに処理をすること
* PowerShellでメールを送信する際、メール全体を暗号化すること


他にも、現時点で不要だった以下の仕様は実装していません。

* 自分が複数のIDをもっている場合、使用するIDを指定すること

　  
#### 独自の仕様

* PowerShellで送信するメールは、本文と添付ファイルを別々に暗号化(本文だけ暗号化しない機能もあり)
* 日本語のみの表示
* 暗号化したメールを送信する際はUTF8でのエンコード
* 作業ディレクトリとして、caffish-ps.ps1のサブディレクトリを作成・使用



開発・動作環境
----------

* OS: Windows7 x64
* .NET Framework: 2.0
* PowerShell: 2.0
* Gpg4win: 2.2.0
* Thunderbird (必要に応じて): 24.0


セットアップ
----------

###Gpg4winのインストール
依存しているGpg4winをインストールします。  
インストール後にパスが通っているかを確認しておきます(通っていない場合は追加)。
　  
　  

###環境設定
`config.example.xml` を `config.xml` へとリネームし、XMLへ以下の環境設定を行います。

####GPG関連
* GPG.LocalUser: 自分の署名鍵のIDを設定します。
* GPG.KeyServer: キーサーバーを設定します。そのままでも問題ないかと思います。


####メール関連
config.example.xmlにはGmailの設定をしてあります。  
Gmail以外の方はそれぞれの設定を変更します(が、環境がないので、試せていません...)


* SMTP.Server.Host: SMTPサーバのサーバ名です。
* SMTP.Server.Port: SMTPサーバのポートです。
* SMTP.Server.EnableSSL: SSL接続する場合は true と入力します。それ以外の値はSSLでは接続しません。
* SMTP.Credential.User: 認証ユーザー名です。
* SMTP.Credential.Password: 認証時のパスワードです。平文でXMLに保存したくない場合は、config.example.xml通り、空欄にしておきます。
* Mail.Address: 送信するときのメールアドレスです。
* Mail.UserName: 送信するときのユーザ名です。
* Thunderbird.Path: メールを送信するときのThunderbird.exeがあるパスを指定します。Portableでも動くようです。
　  
　  

###メールの件名・本文の設定
`mail_content.ps1`を開き、必要に応じてヒアドキュメントの内容を修正します。
　  
　  
###Thunderbirdの設定
メール送信と暗号化をThunderbirdに行わせる場合、事前にThunderbirdにSMTPなどの送信関係の設定を行います。  
合わせて、暗号化するためのアドオン Enigmail もThunderbirdにインストールしておきます。  
[ADD-ONS - Enigmail](https://addons.mozilla.org/ja/thunderbird/addon/enigmail/)




実行方法
----------
    \path\to\caffish-ps.ps1 <送信相手の鍵ID1> <送信相手の鍵ID2>
で実行することができます。

いくつかオプションを用意しているので、以下のヘルプコマンドによりご確認ください。

    Get-Help \path\to\caffish-ps.ps1 -detailed

なお、初めてPowerShellを実行する場合、以下などを参考に権限をRemoteSignedなどに変更しておきます。  
[@IT - PowerShellスクリプトの実行セキュリティ・ポリシーを変更する](http://www.atmarkit.co.jp/fwin2k/win2ktips/1023ps1sec/ps1sec.html)



クレジット
----------
### Gpg4win 
[公式ページ：Gpg4win](http://www.gpg4win.org/license.html)



ライセンス
----------
MIT