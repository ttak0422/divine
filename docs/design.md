# Design requirements

## 基本方針

- Pure Nix で構成を宣言・解決し、軽量な Lua runtime で動的に読み込む。
- 基本方針 Nix で Neovim 構成を定義、ビルド時に必要なファイル配置、軽量 runtime による動的ロード
- 管理対象プラグインとその依存は起動時ロード対象も原則 opt に配置する。after関連の読み込みはユーザ責任とする。
- 起動時対象と遅延対象を別入力に分けず、共通の plugin 定義で扱う。非遅延指定の対象も opt のまま起動時に明示ロードし、start 配置へ切り替えない。読込を担う runtime は init 中から利用可能にする。
- トップレベルと依存の両方で package 単体または同じ詳細定義を受け取り、依存内にも依存を再帰的に書ける。
- プラグイン固有設定は Lua で書く。Nix の settings 属性を setup 引数へ自動変換する仕組みは今回不要とする。
- 起動時の共通設定と、対象の読込前後に実行する設定を区別する。具体的な属性名・関数名と loader / wrapper の実装方式は未決とする。


## 解決戦略

- ユーザーが循環を含む依存関係を自由に記述する
- Tarjan法などでSCCを抽出する
- 各SCCを1つのロード単位として扱う
- SCC間の依存関係をDAGとして処理する
- SCC内部では全プラグインのRuntimeを準備してからプラグイン読み込みタイミングに関連する設定を実行する。


## I/F 設計

inline lsp, treesitter前提でnixを利用した構築

### 定義に必要な表現力

起動時に読む対象と遅延して読む対象を別の入力リストに分けず、同じ定義形式で扱う。
トップレベルにも依存にも、package 単体または同じ詳細定義を記述できる。**package 単体は省略形であり、依存の制約ではない。**
詳細定義には、対象 package、読込時期、読込前後の Lua 設定、依存などを記述でき、依存の中へさらに同じ詳細定義を再帰的に書ける。

プラグイン固有の設定は Lua 本文または Lua ファイルで書く。Nix の属性からプラグイン固有の setup 引数を自動生成する仕組みは必要としない。
起動時の共通 Lua 設定は、対象を読む前後に実行する設定とは分ける。

### 記述例と名前の扱い

以下は表現力を確認するための **未実装の記述例**である。`plugins`、`plugin`、`dependPlugins`、`lazy`、`preConfig`、`config`、`onCommands`、`extraPackages` は、この例を読むための仮称であり、確定した API 名ではない。
確定要件は名前ではなく、共通定義・再帰的な依存・設定の実行タイミング・配置とロードの動作である。正式な属性名、既定値、schema、実装関数は別途決める。

```nix
{ pkgs, ... }:
{
  plugins = [
    # トップレベルでも依存でも package 単体を使える。
    pkgs.vimPlugins.vim-repeat

    {
      plugin = pkgs.vimPlugins.telescope-nvim;
      lazy = true;
      dependPlugins = [
        pkgs.vimPlugins.plenary-nvim
        # 依存にも同じ詳細定義を書き、さらに依存をネストできる。
        {
          plugin = pkgs.vimPlugins.vim-startuptime;
          lazy = false; # この定義も opt のまま起動時にロードする。
          preConfig = # lua
            ''
              vim.g.startuptime_tries = 10
            '';
          config = # lua
            ''
              vim.keymap.set("n", "<leader>st", "<cmd>StartupTime<cr>")
            '';
          dependPlugins = [ pkgs.vimPlugins.vim-repeat ];
        }
      ];
      onCommands = [ "Telescope" ];
      extraPackages = [ pkgs.ripgrep pkgs.fd ];
      config = builtins.readFile ./lua/telescope.lua;
    }
  ];
}
```

この例では、トップレベルと依存の両方に package 単体と詳細定義を混在させ、依存の詳細定義にも読込前後の設定とネストした依存を置いている。
`Telescope → vim-startuptime → vim-repeat` は再帰構造を示す説明用の依存であり、各プラグインの必須依存を示すものではない。
非遅延を明示した詳細定義は、依存内にあっても opt のまま起動時ロードの対象になる。親の読込時期を依存へ自動継承する指定ではない。
package 単体・読込時期の指定省略・trigger がない場合の既定動作は未決である。

例の読込後設定が参照する Lua ファイルには、次のように本体の API を使う処理を書く。

```lua
require("telescope").setup({})
```

読込前設定の例は、本体の読込時に参照される `vim.g.startuptime_tries` を先に渡している。読込後設定の例は、本体を読んだ後に Lua の設定 API を呼ぶ。
Nix 内に Lua を直接書く場合は `# lua` の注釈を付け、別ファイルへ分ける場合も Lua のまま編集する。

### 正規化・同一性・循環

Nix 側で package 単体を詳細定義と共通に扱える形へ正規化し、ネストした依存を検証・graph 化する。詳細定義を依存に書けないという制約には置き換えない。
同一 package の複数出現について、同一性の基準、設定のマージ、異なる読込時期・設定値の競合処理は未決とする。例では `vim-repeat` が2箇所に出るが、黙って統合・破棄する仕様を示してはいない。
循環を含む強連結成分（SCC）を一つのロード単位として扱う。依存 graph の循環と、Nix 値を直接循環させた場合の評価は別問題であり、循環の入力表現と有限な正規化方法は未決とする。

### 配置と設定の実行タイミング

管理対象とその依存は原則 opt に配置する。**非遅延指定の対象も opt のまま、起動時に明示ロードする。** 非遅延指定は start 配置への切替を意味しない。
記述例の `lazy = false` はこの非遅延指定を表す仮の書き方である。遅延対象は指定した trigger で読む。

```text
起動時の共通設定: 対象の本体を必要とするかに関係なく init で実行
対象のロード: 読込前の設定（必要な場合）→ 読込（既定 packadd）→ 読込後の設定
非遅延対象（opt）: 起動時にこの順で明示ロード
trigger 付き遅延対象（opt）: 最初の trigger 時に同じ順で実行
```

| 設定の役割 | 書く内容の例 |
| --- | --- |
| 読込前に実行する設定 | 本体が読込時に参照する global 値、必要な依存準備 |
| 読込後に実行する設定 | 本体の Lua API による setup、本体 API を使うキー割当 |
| 起動時に行う共通 Lua 設定 | キーの接頭辞、本体を読む command を呼ぶキー割当 |

起動時の共通 Lua 設定の例を示す。入力先となる属性名や第三の plugin field の採用は確定しない。

```lua
vim.g.mapleader = " "
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
```

起動時ロードでも遅延ロードでも、読込前の設定・読込・読込後の設定という関係は同じである。
loader / wrapper の実装方式や外部ライブラリの採用は未決であり、この記述例だけから決めない。

### 遅延読込の契機

遅延読込は次の5種類を要件として保持する。これらは機能の説明であり、トリガーを表す属性名・関数名は未決である。

| 契機 | 期待する動作 | 条件の例 |
| --- | --- | --- |
| Neovim のイベント | 指定イベントが発生した時点で対象を読む | 挿入モードへ入るイベント |
| command の呼出し | 対象を読み、呼び出された command の処理につなぐ | `:Telescope` |
| buffer の filetype | filetype 条件に一致したときに対象を読む | `nix` / `lua` の buffer |
| キー操作 | 対象を読んで、そのキー操作に対応する処理につなぐ | `<leader>ff` の操作 |
| Lua module の require | 必要な本体を読んでから、要求された module の解決につなぐ | `require("telescope.builtin")` |

どの契機でも、対象は opt 配置のまま、必要な読込前設定・読込・読込後設定という共通の流れに入る。
module 名はプラグイン名とは別に扱う。キー操作そのものをロード契機にする機能は、init に command 呼出し用のキー割当を書くだけの例とは区別する。
単一条件・複数条件・未指定を表現できることも保持する。条件の記法、module 名の照合範囲、最初の操作やイベントの引継ぎ方法などは実装時に定め、現時点で動作検証済みとはしない。
イベント条件の具体化や、他の読込を契機とする方式など、参考資料にだけ存在する個別 API の機能を、この表だけから追加の確定要件にはしない。

### after/ の読込仕様

既定の読込は通常の `packadd` とする。**起動完了後に opt プラグインを遅延ロードしても `after/plugin` は自動 source しない。**
`after/plugin` が必要な対象だけ、利用者側の明示的な設定、手動 source、読込処理の差し替え等で対応する。補助ライブラリの既定依存や自動導入は決めない。

init 中に `packadd` した対象の `after/` は runtimepath の末尾へ加わり、通常のプラグイン読込が有効なら後続の Neovim 標準 `after/plugin` 読込段階で扱われる。
init 中にも別途 source する独自の読込処理は二重実行の可能性があるため、既定にはしない。
読込後の設定は読込処理が戻った後に実行するものであり、標準 `after/plugin` 全体の読込完了を保証しない。

`after/ftplugin` は `FileType` に応じて `ftplugin` を runtime 検索する別経路である。`packadd` や読込後設定によって `after/` ディレクトリ内を全部一括実行する仕様にはしない。
この節は読込仕様を定めるものであり、独自の読込処理を実装・実行検証したという意味ではない。

## 実装状態

この文書は要求する振る舞いを記述する。現在の足場は有限な入力定義の確認と、読込前・読込・読込後の小さな実行処理までである。
配置、生成、依存 graph と SCC、遅延トリガー、同一性・競合・循環の解決は未実装であり、詳細は TODO.md に記録する。
属性名は仮称であり、記述例をそのまま実行可能な完成 API として扱わない。

## コーディングルール

git-hooks.nix (prek) の提供するルールに従う

### nix

- nixdoc (https://github.com/nix-community/nixdoc) 準拠


### lua

- linterやformatterに従う範囲でワンライナー的な記述を心掛ける


## サポート

- イベント、command、filetype、キー操作、Lua module の require を契機とする遅延読込。単一条件・複数条件・未指定を表現できること。具体的な記法と実装方式は未決
- doc 出力
- 設定ファイルを分割して記述できること
- 外部コマンド等の実行時依存を追加できること
- after/ftdetectのような形式の設定もサポート


## サポートしない

- denops native サポート (deno runtime EOLのため)
- hot swap / プラグイン全体の unload・reload を標準機能にすること
