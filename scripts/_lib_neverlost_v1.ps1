Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-SshKeygen(){ $c=Get-Command ssh-keygen -ErrorAction SilentlyContinue; if($null -eq $c){ throw "SSH_KEYGEN_NOT_FOUND" }; $c.Source }

function SshY-Sign([string]$Namespace,[string]$KeyPath,[string]$MessagePath,[string]$SigOut){
  $ssh = Find-SshKeygen
  foreach($p in @($KeyPath,$MessagePath)){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw ("SIGN_MISSING_FILE: " + $p) } }
  $tmpSig = $MessagePath + ".sig" 
  if(Test-Path -LiteralPath $tmpSig -PathType Leaf){ Remove-Item -LiteralPath $tmpSig -Force -ErrorAction Stop }
  $p = Start-Process -FilePath $ssh -ArgumentList @("-Y","sign","-f",$KeyPath,"-n",$Namespace,$MessagePath) -NoNewWindow -Wait -PassThru
  if($p.ExitCode -ne 0){ throw ("SSHKEYGEN_SIGN_FAILED exit=" + $p.ExitCode) }
  if(-not (Test-Path -LiteralPath $tmpSig -PathType Leaf)){ throw ("SIGNATURE_NOT_CREATED: " + $tmpSig) }
  $dir = Split-Path -Parent $SigOut; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Move-Item -LiteralPath $tmpSig -Destination $SigOut -Force
}

function SshY-Verify([string]$Namespace,[string]$AllowedSigners,[string]$Principal,[string]$SigPath,[string]$MessagePath){
  $ssh = Find-SshKeygen
  foreach($p in @($AllowedSigners,$SigPath,$MessagePath)){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw ("VERIFY_MISSING_FILE: " + $p) } }
  $bytes = [System.IO.File]::ReadAllBytes($MessagePath)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $ssh
  $psi.Arguments = ("-Y verify -f `"{0}`" -I `"{1}`" -n `"{2}`" -s `"{3}`"" -f $AllowedSigners,$Principal,$Namespace,$SigPath)
  $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.UseShellExecute=$false
  $p = New-Object System.Diagnostics.Process; $p.StartInfo=$psi; [void]$p.Start()
  $p.StandardInput.BaseStream.Write($bytes,0,$bytes.Length); $p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd(); $err=$p.StandardError.ReadToEnd(); $p.WaitForExit()
  if($p.ExitCode -ne 0){ throw ("SSHKEYGEN_VERIFY_FAILED exit=" + $p.ExitCode + " err=" + $err) }
  $out
}
