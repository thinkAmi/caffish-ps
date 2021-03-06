#-------------------------------------------
# Get-Helpで表示するヘルプ内容
#-------------------------------------------

<#
  .SYNOPSIS
  指定したIDの公開鍵に署名をして、メール送信をします。
  なお、複数のIDを指定できますが、それぞれのIDの区切りは半角スペースとなります。
  .DESCRIPTION
  メールの送信手段は、Thunderbird・System.Web.Mail・System.Net.Mail(デフォルト)のいずれかとなります。
  .PARAMETER thunderbird
  Thunerbirdでメールを送信します。
  .PARAMETER obsolete
  .Net1.1でも使えるSystem.Web.Mailでメールを送信します。
  .PARAMETER bcc
  メールの送信者(From)をBccへ追加します。
  .PARAMETER no_download
  キーサーバから公開鍵をダウンロードせず、手元の鍵束にある公開鍵を利用して署名を行います。
  .PARAMETER unencrypted_body
  メール本文は暗号化せず、添付の署名付公開鍵のみ暗号化します。
  .EXAMPLE
  gpg_helper.ps1 "相手のIDその1" "相手のIDその2"
  config.xmlの内容に従い、System.Net.Mailを使って、それぞれにメールを送信します。
  .EXAMPLE
  gpg_helper.ps1 "相手のIDその1" "相手のIDその2" -thunderbird -obsolete
  メール送信のオプションが複数指定されていますが、Thunderbirdの方が優先されるため、Thunderbirdで送信します。
  
#>

#-------------------------------------------
# コマンドラインパラメータ：スクリプトの先頭に記述する必要あり
#-------------------------------------------
Param(
  [switch]$thunderbird,
  [switch]$obsolete,
  [switch]$bcc,
  [switch]$no_download,
  [switch]$unencrypted_body
)

#--------------------------------------------------------
# フィンガープリントのタイトルを表示
#--------------------------------------------------------
function ShowFingprintTitle(){
    return @"

---------------------------
フィンガープリント情報
---------------------------
"@
}

#--------------------------------------------------------
# 送信予定のメールユーザ名・アドレスを表示
#--------------------------------------------------------
function ShowRecipientInfo($toUser, $toAddress){
    return @"

===================
送信予定の情報
===================
ユーザ名: $toUser
アドレス: $toAddress
"@
}

#--------------------------------------------------------
# 処理を続行するかの確認・選択
#--------------------------------------------------------
function ConfirmContinuation($comment){
    $type = "System.Management.Automation.Host.ChoiceDescription"
    $yes = New-Object $type("&Yes", "続行する")
    $no = New-Object $type("&No", "取りやめる")
    
    $choice = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    $answer = $host.ui.PromptForChoice("<確認>", $comment + "`nこのIDの処理を続けますか？", $choice, 1)
    
    return $answer
}

#--------------------------------------------------------
# uid行のうち、最初のものを取得
#--------------------------------------------------------
function SelectFirstUIDLine($fingerprint){
    # uidが2行以上ある場合も考慮し、Select-Object で最初のものに絞る
    return $fingerprint -split "`n" | Where-Object { ($_ -match "^uid") -and ($_ -match "<.+>") } | Select-Object -First 1
}

#--------------------------------------------------------
# uid行をメールユーザー名へと変換
#--------------------------------------------------------
function ConvertToMailUserName($line){
    return ($line -replace "(^uid | <.+>)", "").Trim()
}

#--------------------------------------------------------
# uid行をメールアドレスへと変換
#--------------------------------------------------------
function ConvertToMailAddress($line){
    # メールアドレスは <> に囲まれているので、そちらを利用
    # -match の結果は戻したくないので、 Out-Null
    $line -match "<.+>" | Out-Null
    
    return $matches[0] -replace "[<>]", ""
}

#--------------------------------------------------------
# 署名時に使用するディレクトリの作成
#--------------------------------------------------------
function NewDirectory($runningDir){
    $signingDir = "$runningDir\signing"
    if ((Test-Path $signingDir) -eq $false){
        New-Item -path $runningDir -name signing -type directory | Out-Null
    }
    
    return $signingDir
}

#--------------------------------------------------------
# 暗号化可能かどうかの確認
#--------------------------------------------------------
function TestEncryptable($userID, $signingDir){
    # 署名時に利用するディレクトリにテスト的なファイルを用意し、それを暗号化できるかどうかで判断する
    # 何らかの理由で存在した場合には、強制的に空ファイルに上書き
    New-Item -path $signingDir -name test -type file -force -value encryptable? | Out-Null
    
    $targetFile = "$signingDir\test"
    & gpg --no-auto-check-trustdb  --trust-model=always --armor --recipient $userID --encrypt $targetFile
    $encryptable = $?
    
    # 終わったので消しておく
    Remove-Item $targetFile
    
    if ($encryptable){
        Remove-Item "$targetFile.asc"
    }
    
    return $encryptable
}

#--------------------------------------------------------
# メール本文を作成
#--------------------------------------------------------
function NewMailBody($fromUser, $toUser, $signingDir, $userID, $keyServer, $isEncryptable){

    $bodyFilePath = "$signingDir\$userID-mail_body"

    # Default(Shift-JIS)ではなく、UTF-8でのエンコードをしておかないと、メールの時に文字化けする
    GetMailBodyTemplate $fromUser $toUser $userID $keyServer | Out-File -FilePath $bodyFilePath -Encoding UTF8

    if ($isEncryptable){
        & gpg  --no-auto-check-trustdb --trust-model=always --encrypt --armor --recipient $userID $bodyFilePath | Out-Null
        
        # 暗号化するとShift-JISのファイルになるので、読み込む時のエンコードに指定
        $encode = [System.Text.Encoding]::GetEncoding("Shift-JIS")
        $path = "$bodyFilePath.asc"
    }
    else{
        $encode = [System.Text.Encoding]::UTF8
        $path = $bodyFilePath
    }
    
    return [System.IO.File]::ReadAllText($path, $encode)
}

#--------------------------------------------------------
# 添付ファイル用の公開鍵ファイルの作成
#--------------------------------------------------------
function NewPublickeyFile($localUser, $userID, $signingDir, $isEncryptable){

    $publickeyPath = "$signingDir\$userID.1.signed-by-$localUser.asc"
    
    if ($isEncryptable){
        # 自分の秘密鍵で署名した相手の公開鍵を、相手の公開鍵を使って暗号化
        # 署名時と同様、相手の公開鍵は常に信頼しておく
        & gpg --export --armor --output $publickeyPath $userID
        & gpg --no-auto-check-trustdb  --trust-model=always --armor --recipient $userID --encrypt $publickeyPath
        
        return "$publickeyPath.asc"
    }
    else{
        & gpg --export --armor --output $publickeyPath $userID
        
        return $publickeyPath
    }   
}

#--------------------------------------------------------
# SMTP用パスワードの生成
#--------------------------------------------------------
function NewPassword($config){
    $password = $config.Configuration.SMTP.Credential.Password
    
    if ([System.String]::IsNullOrEmpty($password)) {
        $secure = Read-Host EnterPassword -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        # BSTR型をクリア
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
   
    return $password
}

#--------------------------------------------------------
# SMTPクライアントの新規作成
#--------------------------------------------------------
function NewSMTP($config){

    $smtp = New-Object System.Net.Mail.SmtpClient
    $smtp.Host = $config.Configuration.SMTP.Server.Host
    $smtp.Port = $config.Configuration.SMTP.Server.Port
    
    if ($config.Configuration.SMTP.Server.EnableSSL -eq 'true'){
        $smtp.EnableSsl = $true
    }
    else{
        $smtp.EnableSsl = $false
    }
    
    $smtp.Credentials = New-Object Net.NetworkCredential
    $smtp.Credentials.UserName = $config.Configuration.SMTP.Credential.User
    $smtp.Credentials.Password = NewPassword $config
    
    return $smtp
}

#--------------------------------------------------------
# ThunderbirdによるMailの送信
# 暗号化などはThunderbirdに任せる
#--------------------------------------------------------
function SendMailByThunderbird($tbPath, $mail, $bcc){
    $option = "to=" + $mail.ToAddress
    
    if ($bcc)
    {
        $option += ",bcc=" + $mail.FromAddress
    }
    
    $option += ",subject=" + $mail.Subject
    $option += ",body=" + $mail.Body
    $option += ",attachment=file:\\" + $mail.AttachmentPath

    & $tbPath -compose $option
}

#--------------------------------------------------------
# System.Web.MailによるMailの送信
# BodyのみエンコーディングはUTF8 (Subjectはプロパティが見当たらないので未指定)
#--------------------------------------------------------
function SendMailByWebMail($config, $mail, $bcc){

    try {
        # System.Webは参照設定しないと使えない
        Add-Type -AssemblyName System.Web
        
        $msg = New-Object System.Web.Mail.MailMessage
        $msg.From = $mail.FromAddress
        $msg.To = $mail.ToAddress
        
        if ($bcc) {
            $msg.Bcc = $msg.From
        }
        
        $msg.Subject = $mail.Subject
        $msg.Body = $mail.Body
        $msg.BodyEncoding = [System.Text.Encoding]::UTF8
        
        $attachment = New-Object System.Web.Mail.MailAttachment $mail.AttachmentPath
        # 以下のコードで "0" が標準出力されてしまうので、 Out-Nullしておく
        $msg.Attachments.Add($attachment) | Out-Null
        
        
        $msg.Fields["http://schemas.microsoft.com/cdo/configuration/sendusing"] = 2
        $msg.Fields["http://schemas.microsoft.com/cdo/configuration/smtpserver"] = $config.Configuration.SMTP.Server.Host
        $msg.Fields["http://schemas.microsoft.com/cdo/configuration/smtpserverport"] = $config.Configuration.SMTP.Server.Port
        $msg.Fields["http://schemas.microsoft.com/cdo/configuration/smtpauthenticate"] = 1
        $msg.Fields["http://schemas.microsoft.com/cdo/configuration/sendusername"] = $config.Configuration.SMTP.Credential.User
        $msg.Fields["http://schemas.microsoft.com/cdo/configuration/smtpusessl"] = $true
        
        # Fieldsにパスワードを渡す際、明示的に型変換をしないと「フィールドの更新に失敗しました。」というエラーが出る
        $pw = NewPassword $config
        $msg.Fields["http://schemas.microsoft.com/cdo/configuration/sendpassword"] = [System.String]$pw
       
        [System.Web.Mail.SmtpMail]::SmtpServer = $config.Configuration.SMTP.Server.Host
    
        "Web.Mailで送信します。"
        [System.Web.Mail.SmtpMail]::Send($msg)
        "Web.Mailで送信しました。`n"
    }
    catch{
        "メールの送信に失敗したため、このIDにはメールを送ることができていません。`n"
        $Error[0]
    }
}

#--------------------------------------------------------
# System.Net.MailによるMailの送信
# Subject・Bodyとも、エンコーディングはUTF8
#--------------------------------------------------------
function SendMailByNetMail($smtp, $mail, $bcc){
    try {
        $msg = New-Object System.Net.Mail.MailMessage
        $msg.From = $mail.FromAddress
        
        $to = New-Object System.Net.Mail.MailAddress $mail.ToAddress, $mail.ToUser
        $msg.To.Add($to)
        
        if ($bcc){
            $msg.Bcc.Add($msg.From)
        }
        
        $msg.Subject = $mail.Subject
        $msg.SubjectEncoding = [System.Text.Encoding]::UTF8


        # Alternateviewsで本文を作成する(.NET4.0以下で、transfer-encodingを7bitにするため)
        $view = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($mail.Body, [System.Text.Encoding]::UTF8, "text/plain")
        $view.TransferEncoding = [System.Net.Mime.TransferEncoding]::SevenBit
        $msg.AlternateViews.Add($view)
       
        
        # 添付ファイル
        $attachment = New-Object System.Net.Mail.Attachment $mail.AttachmentPath
        $attachment.TransferEncoding = [System.Net.Mime.TransferEncoding]::SevenBit
        $msg.Attachments.Add($attachment)

        "Net.Mailで送信します"
        $smtp.Send($msg)
        "Net.Mailで送信しました。`n"
        
    }
    catch {
        "メールの送信に失敗したため、このIDにはメールを送ることができていません。`n"
        $Error[0]
    }
    finally {
        $msg.Dispose()
    }
}

#=================================================
# エントリポイント
#=================================================

# config.xmlを読み込み
$private:runningDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$private:config = [xml](Get-Content "$runningDir\config.xml")
$private:localUser = $config.Configuration.GPG.LocalUser
$private:keyServer = $config.Configuration.GPG.KeyServer
$private:fromAddress = $config.Configuration.Mail.Address
$private:fromUser = $config.Configuration.Mail.UserName

# Thunderbird.exeがあるパスを読み込んでおく
$private:tbPath = $config.Configuration.Thunderbird.Path

# 署名時に利用するディレクトリを作成しておく
$signingDir = NewDirectory $runningDir


# メール送信対象のIDはパラメータなしの引数で指定するため、$args に格納される
# $argsをForEach-Object(foreach/%がエイリアス) で回して、$_で一つのIDごとに処理をする
$args | ForEach-Object{

    # 例外が出た場合は、そのIDの処理をしない
    try {

        if ($no_download -eq $false){
            # 公開鍵サーバーより、公開鍵を取得する
            & gpg --keyserver $keyServer --recv-key $_
            
            # $?で、直前のコマンドの実行結果(True/False)を拾える
            if ($? -eq $false){
                "ID: $_ の公開鍵がダウンロードできなかったため、このIDの処理をやめました。"
                continue
            }
        }
        
        
        # 公開鍵のフィンガープリントを表示する
        $private:fingerprint = & gpg --fingerprint $_
        
        if ($? -eq $false){
            "ID: $_ の公開鍵のフィンガープリントを取得できなかったため、このIDの処理をやめました。"
            continue
        }
        
        
        ShowFingprintTitle
        $fingerprint
        if ((ConfirmContinuation "手元の情報とフィンガープリントは一致している場合のみ、署名をするために処理を続けてください。") -ne 0){
            "このIDの処理をやめました"
            continue
        }
        
             
        # 相手の公開鍵に自分の秘密鍵で署名(初回、秘密鍵のパスワードを求められる)
        # なお、複数のuidがある場合、「--batch --yes」としても「gpg: Sorry, we are in batchmode - can't get input」と
        # 表示されて署名ができないので、--sign-key時は --batch で処理しないようにする
        # また、--no-auto-check-trustdb --trust-model=always を追加して、常に信頼して署名する
        & gpg --default-key $localUser --no-auto-check-trustdb --trust-model=always --sign-key $_
        
        if ($? -eq $false){
            "ID: $_ の公開鍵に署名ができなかったため、このIDの処理をやめました。"
            continue
        }
        
        
        # 送信先を取得する
        # 公開鍵のフィンガープリントから、一番最初のuid行(氏名やメールアドレスがある行)を取得
        $private:line = SelectFirstUIDLine($fingerprint)
        
        # 関数の引数を減らすため、メール関連の情報が入ったハッシュを用意する
        $private:mail = @{FromAddress = $fromAddress; FromUser = $fromUser}
        $mail.ToUser = ConvertToMailUserName($line)
        $mail.ToAddress = ConvertToMailAddress($line)
        
        
        # 送信先の確認
        ShowRecipientInfo $mail.ToUser $mail.ToAddress
        if ((ConfirmContinuation "署名済の公開鍵を相手にメールしますか？`nメールしない場合、署名済の公開鍵を削除します。") -ne 0){
            & gpg --delete-key $_
            "このIDの署名済公開鍵を削除しました。"
            continue
        }
        
        
        # 暗号化が可能な鍵かどうかチェック
        $private:isEncryptable = TestEncryptable $_ $signingDir
        if ($isEncryptable -eq $false){
            "`n暗号化できない公開鍵のため、メールは暗号化せずに送信します。`n"
        }
        
        
        # Thunderbirdで送信する場合は、Thunderbird側で暗号化する
        if ($thunderbird) {
            $isEncryptable = $false
        }
       
        
        # 添付ファイル用公開鍵の作成
        $mail.AttachmentPath = NewPublickeyFile $localUser $_ $signingDir $isEncryptable

        
        # mail_content.ps1にメールのSubjectとBodyがあるため、そのps1ファイルを使えるようにする
        # Join-Pathを使いたかっただけなので、「. "$runningDir\mail_content.ps1"」でも可
        . (Join-Path $runningDir "mail_content.ps1")
        
        
        # 件名
        $mail.Subject = GetMailSubject
        
        
        # ps1ファイルより、ヒアドキュメントで書かれたメール本文を取得
        if ($unencrypted_body){
            $mail.Body = NewMailBody $mail.FromUser $mail.ToUser $signingDir $_ $keyServer $false
        }
        else{
            $mail.Body = NewMailBody $mail.FromUser $mail.ToUser $signingDir $_ $keyServer $isEncryptable
        }
    }
    catch {
        "エラーが発生したため、このIDの処理をやめました"
        $Error[0]
        
        continue
    }
    
    
    # 送信手段別のメール送信
    switch($true)
    {
        # Thunderbirdを起動してメールを送信(暗号化などは手動)
        # ThunderbirdにSMTPの設定 + アドオン「Enigmail」を入れておく
        $thunderbird { SendMailByThunderbird $tbPath $mail $bcc; break }
        
        
        # Obsoleteになっている、Web.Mailにて送信
        $obsolete { SendMailByWebMail $config $mail $bcc; break }
        
        
        # Net.Mailにて送信
        default {
            if ($private:smtp -eq $null){
                # XMLにパスワードがない場合、パスワード入力することになるので、メッセージ表示
                # NewSMTPの中で表示させるようにすると、$smtpの中にメッセージが混じってしまうので、ここでメッセージを出しておく
                if ([System.String]::IsNullOrEmpty($config.Configuration.SMTP.Credential.Password)){
                    "メールを送信するアカウントのパスワードを入力してください。"
                }
                $smtp = NewSMTP $config
            }
            SendMailByNetMail $smtp $mail $bcc
        }
    }
}

"すべての処理が完了しました。"