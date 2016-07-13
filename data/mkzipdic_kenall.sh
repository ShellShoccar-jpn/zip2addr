#! /bin/sh

#####################################################################
#
# MKZIPDIC_KENALL.SH
# 日本郵便公式の郵便番号住所CSVから、本システム用の辞書を作成（地域名）
# Written by Rich Mikan(richmikan[at]richlab.org) at 2016/07/14
#
# Usage : mkzipdic.sh -f
#         -f ... ・サイトにあるCSVファイルのタイプスタンプが、
#                  今ある辞書ファイルより新しくても更新する
#
# [出力]
# ・戻り値
#   - 作成成功もしくはサイトのタイムスタンプが古いために作成する必要無
#     しの場合は0、失敗したら0以外
# ・成功時には辞書ファイルを更新する。
#
######################################################################


######################################################################
# 初期設定
######################################################################

# --- 変数定義 -------------------------------------------------------
dir_MINE="$(d=${0%/*}/; [ "_$d" = "_$0/" ] && d='./'; cd "$d"; pwd)" # このshのパス
readonly file_ZIPDIC="$dir_MINE/ken_all.txt"                         # 郵便番号辞書ファイルのパス
readonly url_ZIPCSVZIP=http://www.post.japanpost.jp/zipcode/dl/oogaki/zip/ken_all.zip
                                                                     # 日本郵便 郵便番号-住所 CSVデータ (Zip形式) URL
readonly flg_SUEXECMODE=0                                            # サーバーがsuEXECモードで動いているなら1

# --- ファイルパス ---------------------------------------------------
PATH='/usr/local/tukubai/bin:/usr/local/bin:/usr/bin:/bin'

# --- 終了関数定義(終了前に一時ファイル削除) -------------------------
exit_trap() {
  trap 0 1 2 3 13 14 15
  [ -n "${tmpf_zipcsvzip:-}" ] && rm -f $tmpf_zipcsvzip
  [ -n "${tmpf_zipdic:-}"    ] && rm -f $tmpf_zipdic
  exit ${1:-0}
}
trap 'exit_trap' 0 1 2 3 13 14 15

# --- エラー終了関数定義 ---------------------------------------------
error_exit() {
  [ -n "$2" ] && echo "${0##*/}: $2" 1>&2
  exit_trap $1
}

# --- テンポラリーファイル確保 ---------------------------------------
tmpf_zipcsvzip=$(mktemp -t "${0##*/}.XXXXXXXX")
[ $? -eq 0 ] || error_exit 1 'Failed to make temporary file #1'
tmpf_zipdic=$(mktemp -t "${0##*/}.XXXXXXXX")
[ $? -eq 0 ] || error_exit 2 'Failed to make temporary file #2'



######################################################################
# メイン
######################################################################

# --- 引数チェック ---------------------------------------------------
flg_FORCE=0
case "${1:-}" in '-f') flg_FORCE=1;; esac

# --- Webアクセスコマンド存在チェック --------------------------------
type curl >/dev/null 2>&1 || type wget >/dev/null 2>&1 || {
  error_exit 3 'No HTTP-GET/POST command found.'
}

# --- ZIP展開コマンド存在チェック ------------------------------------
type unzip >/dev/null 2>&1 || type gunzip >/dev/null 2>&1 || {
  error_exit 4 'No ZIP extracter command found.'
}

# --- サイト上のファイルのタイムスタンプを取得 -----------------------
timestamp_web=$(if type curl >/dev/null 2>&1; then                           #
                  curl -sLI        $url_ZIPCSVZIP                            #
                else                                                         #
                  wget -S --spider $url_ZIPCSVZIP | sed 's/^ *//'            #
                fi                                                           |
                awk '                                                        #
                  BEGIN{                                                     #
                    status = 0;                                              #
                    d["Jan"]="01";d["Feb"]="02";d["Mar"]="03";d["Apr"]="04"; #
                    d["May"]="05";d["Jun"]="06";d["Jul"]="07";d["Aug"]="08"; #
                    d["Sep"]="09";d["Oct"]="10";d["Nov"]="11";d["Dec"]="12"; #
                  }                                                          #
                  /^HTTP\// { status = $2; }                                 #
                  /^Last-Modified/ {                                         #
                    gsub(/:/, "", $6);                                       #
                    ts = sprintf("%04d%02d%02d%06d" ,$5,d[$4],$3,$6);        #
                  }                                                          #
                  END {                                                      #
                    if ((status>=200) && (status<300) && (length(ts)==14)) { #
                      print ts;                                              #
                    } else {                                                 #
                      print "NOT_FOUND";                                     #
                    }                                                        #
                  }'                                                         )
[ "$timestamp_web" != 'NOT_FOUND' ] || error_exit 5 'The zipcode CSV file not found on the web'
printf '%s\n' "$timestamp_web" | grep -Eq '^[0-9]{14}$'
[ $? -eq 0 ] || timestamp_web=$(TZ=UTC/0 date +%Y%m%d%H%M%S) # 取得できなければ現在日時を入れる

# --- 手元の辞書ファイルのタイムスタンプと比較し、更新必要性確認 -----
while [ $flg_FORCE -eq 0 ]; do
  # 手元に辞書ファイルはあるか?
  [ ! -f "$file_ZIPDIC" ] && break
  # その辞書ファイル内にタイムスタンプは記載されているか?
  timestamp_local=$(head -n 1 "$file_ZIPDIC" | awk '{print $NF}')
  printf '%s\n' "$timestamp_local" | grep -Eq '^[0-9]{14}$' || break
  # サイト上のファイルは手元のファイルよりも新しいか?
  [ $timestamp_web -gt $timestamp_local ] && break
  # そうでなければ何もせず終了(正常)
  exit 0
done

# --- 郵便番号CSVデータファイル(Zip形式)ダウンロード -----------------
if   type curl >/dev/null 2>&1; then
  curl -s      $url_ZIPCSVZIP > $tmpf_zipcsvzip
else
  wget -q -O - $url_ZIPCSVZIP > $tmpf_zipcsvzip
fi
[ $? -eq 0 ] || error_exit 6 'Failed to download the zipcode CSV file'

# --- 郵便番号辞書ファイル作成 ---------------------------------------
if   type unzip  >/dev/null; then                                 #
  unzip -p $tmpf_zipcsvzip                                        #
elif type gunzip >/dev/null; then                                 #
  gunzip <$tmpf_zipcsvzip 2>/dev/null || {                        #
    error_exit 7 'No Zip archive extracter found (unzip)'         #
  }                                                               #
else                                                              #
  error_exit 8 'No Zip archive extracter found (unzip or gunzip)' #
fi                                                                |
# 日本郵便 郵便番号-住所 CSVデータ(Shift_JIS)                     #
if   type iconv >/dev/null 2>&1; then                             #
  iconv -c -f SHIFT_JIS -t UTF-8                                  #
elif type nkf   >/dev/null 2>&1; then                             #
  nkf -Sw80                                                       #
else                                                              #
  error_exit 9 'No KANJI convertors found (iconv or nkf)'         #
fi                                                                |
# 日本郵便 郵便番号-住所 CSVデータ(UTF-8変換済)                   #
$dir_MINE/../commands/parsrc.sh                                   | # CSVパーサー(自作コマンド)
# 1:行番号 2:列番号 3:CSVデータセルデータ                         #
awk '$2~/^3|7|8|9$/'                                              |
# 1:行番号 2:列番号(3=郵便番号,7=都道府県,8=市区町村,9=町) 3:データ
awk 'BEGIN{z="#"; p="generated"; c="at"; t="'$timestamp_web'"; }  #
     $1!=line      {pl();z="";p="";c="";t="";line=$1;          }  #
     $2==3         {z=$3;                                      }  #
     $2==7         {p=$3;                                      }  #
     $2==8         {c=$3;                                      }  #
     $2==9         {t=$3;                                      }  #
     END           {pl();                                      }  #
     function pl() {print z,p,c,t;                             }' |
sed 's/（.*//'                                                    | # 地域名住所文字列で小括弧以降は使えないので除去する
sed 's/以下に.*//'                                                > $tmpf_zipdic # 「以下に」の場合も同様
# 1:郵便番号 2:都道府県名 3:市区町村名 4:町名
[ -s $tmpf_zipdic ] || error_exit 9 'Failed to make the zipcode dictionary file'
mv $tmpf_zipdic "$file_ZIPDIC"
[ "$flg_SUEXECMODE" -eq 0 ] && chmod go+r "$file_ZIPDIC" # suEXECで動いていない場合はhttpdにも読めるようにする


######################################################################
# 正常終了
######################################################################

exit 0
