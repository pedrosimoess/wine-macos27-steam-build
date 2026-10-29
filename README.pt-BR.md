# wine-macos27-steam-build

[English](README.md)

Compila o Wine do **código aberto do CrossOver**, publicado pela CodeWeavers, num Mac com Apple Silicon, para usar com o [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) e rodar a Steam de Windows.

Isso resolveu uma coisa que o Wine 11 comum não resolvia: **os lobbies multiplayer da Steam**. Com o Wine 11.0 do Gcenx, The Binding of Isaac: Repentance+ ficava preso em "Creating lobby" e não conseguia entrar no lobby de um amigo. Com este build, criar e entrar em lobbies funciona na hora.

> Este projeto não tem relação com a CodeWeavers nem é endossado por ela. CrossOver é marca registrada da CodeWeavers, Inc. Aqui só se usa o código que eles publicam sob a LGPL. Se puder, [compre o CrossOver](https://www.codeweavers.com/crossover): ele financia boa parte do desenvolvimento do Wine e inclui as partes de código fechado que este build não tem.

## Testado em

| | |
| --- | --- |
| Mac | MacBook Air M4 |
| macOS | 27.0.1, Command Line Tools 27 |
| Código do Wine | CrossOver 26.3.0 (Wine 11.0) |
| App base | Gcenx Wine Stable 11.0_1 |
| steam-on-m1-wine | [fork do alexwinskii](https://github.com/alexwinskii/steam-on-m1-wine/tree/macos26-fixes), branch `macos26-fixes` |
| Jogo | The Binding of Isaac: Rebirth + Repentance+, co-op online |

Outros jogos e o macOS 26 devem funcionar, mas não foram testados.

## Como usar

**1. Instale o steam-on-m1-wine e entre na Steam uma vez.** Siga o README dele; a instalação mínima basta. O teste foi feito com a branch `macos26-fixes` do fork, que corrige a instalação em macOS e Homebrew recentes; o projeto original pode já funcionar também.

```bash
git clone -b macos26-fixes https://github.com/alexwinskii/steam-on-m1-wine.git ~/steam-on-m1-wine
cd ~/steam-on-m1-wine
bash install.sh --minimal
```

Isso instala o `Wine Stable.app` do Gcenx (que o `build.sh` reaproveita) e cria o prefixo da Steam em `~/.wine-steam`.

**2. Compile o Wine CX.** O primeiro build leva uns 15 minutos num M4 (mais em Macs mais antigos) e uns 6 GB de disco:

```bash
git clone https://github.com/pedrosimoess/wine-macos27-steam-build.git
cd wine-macos27-steam-build
bash build.sh
```

O script instala as ferramentas do Homebrew que faltarem, baixa o código do CrossOver direto da CodeWeavers (conferindo o SHA-256), compila e cria `~/Games/wine-cx/Wine CX.app`.

**3. Abra a Steam com o Wine CX:**

```bash
bash steam-cx.sh
```

Na primeira vez o prefixo é atualizado para a nova versão do Wine, o que leva um minuto. Para voltar ao Wine 11 comum, abra o steam-on-m1-wine normalmente.

Para não mexer no prefixo original, faça uma cópia e aponte o lançador para ela:

```bash
cp -cR ~/.wine-steam ~/.wine-steam-cx
WINEPREFIX=~/.wine-steam-cx bash steam-cx.sh
```

### DirectX 10/11 (opcional)

De fábrica, o Wine CX só oferece Direct3D 11 no nível 9_3, e a maioria dos jogos DirectX 11 nem abre. O CrossOver resolve isso com o DXVK e o MoltenVK modificado da CodeWeavers, que vêm no mesmo pacote de código. O `build-graphics.sh` compila os dois; ele precisa do Xcode completo com a licença aceita e leva uns 15 minutos:

```bash
sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license
bash build-graphics.sh
./cx dxvk on       # com a Steam fechada
```

Depois disso os jogos recebem Direct3D 11 (nível 11_0) em 32 e 64 bits. Os programas da própria Steam continuam com o DirectX do Wine, por meio de exceções por programa, do mesmo jeito que o CrossOver configura: com o DXVK, o web helper da Steam nunca abre a janela. Para isso funcionar, o `./cx dxvk on` altera uma linha do `launch-steam.sh` do steam-on-m1-wine (o original fica salvo como `launch-steam.sh.orig`).

O `./cx dx9 on` passa o Direct3D 9 pelo DXVK também. O Direct3D 9 do próprio Wine já funciona, então esse é opcional.

### O painel `cx`

| Comando | O que faz |
| --- | --- |
| `./cx` | Mostra o que está ligado |
| `./cx steam` / `./cx stop` | Abre a Steam / fecha a Steam e tudo do Wine |
| `./cx dxvk on\|off` | DirectX 10/11 pelo DXVK |
| `./cx dx9 on\|off` | DirectX 9 pelo DXVK |
| `./cx avx on\|off` | Anuncia AVX/AVX2 aos jogos. O Rosetta executa essas instruções, mas só as anuncia com `ROSETTA_ADVERTISE_AVX=1`; o CrossOver liga isso por jogo |
| `./cx retina on\|off` | Modo alta resolução (interface nítida na tela Retina). Experimental |

Cada `off` desfaz o seu `on`, e toda mudança que mexe no prefixo pede que a Steam esteja fechada.

### Configuração

Os scripts leem variáveis de ambiente. `bash build.sh --help` lista todas.

| Variável | Padrão | Usada por |
| --- | --- | --- |
| `WINE_CX_DIR` | `~/Games/wine-cx` | os dois |
| `OUT_APP` | `$WINE_CX_DIR/Wine CX.app` | `build.sh` |
| `GCENX_APP` | `/Applications/Wine Stable.app` | `build.sh` |
| `JOBS` | número de núcleos | `build.sh` |
| `STEAM_ON_M1_WINE` | `~/steam-on-m1-wine` | `steam-cx.sh` |
| `WINE_APP` | `$WINE_CX_DIR/Wine CX.app` | `steam-cx.sh` |
| `WINEPREFIX` | `~/.wine-steam` | `steam-cx.sh` |
| `WINEMSYNC` | `1` | `steam-cx.sh` |

### Problemas comuns

- **Janela da Steam preta depois de uma atualização.** A Steam sobrescreveu o wrapper do `steamwebhelper` do steam-on-m1-wine. Feche a Steam e rode o `steam-cx.sh` de novo: ele reinstala o wrapper toda vez que abre.
- **A Steam pede login de novo.** O prefixo foi aberto com o usuário do Windows `crossover` (o padrão do CrossOver). O `steam-cx.sh` define `CX_REPORT_REAL_USERNAME=1` para evitar isso. Se abrir o Wine CX de outro jeito, defina também.
- **Fechar tudo do Wine:** `pkill -9 -i -f '\.exe|wineserver|wine64-preloader'`

## Recompilar e desinstalar

Mantendo `src/` e `build/` em `~/Games/wine-cx`, o `build.sh` só recompila o que mudou. A pasta de build depende do código, então mova ou apague as duas juntas.

Para desinstalar, apague `~/Games/wine-cx`. O `build.sh` nunca modifica os prefixos nem o `Wine Stable.app`.

## O que foi preciso para compilar o Wine do CrossOver no macOS 27

O build usa as mesmas opções do wine-stable do Gcenx, mais correções para problemas que aparecem no macOS 27:

| Problema | Correção no `build.sh` |
| --- | --- |
| As Command Line Tools só existem em arm64, então o `xcrun` e os atalhos de `/usr/bin` quebram no Rosetta | Só o `configure` roda em x86_64. `clang` e `make` são chamados nativos da pasta das CLT, com `-arch x86_64` |
| O bison 2.3 das CLT passa na frente do Homebrew | bison e flex do Homebrew vêm primeiro no `PATH` |
| As dylibs do Gcenx têm install name sem versão, e o configure detecta SONAMEs errados | SONAMEs passados explicitamente com `ac_cv_lib_soname_*` |
| O `sfnt2fon` aborta porque o dyld não acha `libfreetype.dylib` | Links das dylibs do Gcenx na pasta de build |
| O `CW HACK 25909` do CrossOver, em `win32u/vulkan.c`, exige `SONAME_LIBVULKAN` | Build `--with-vulkan` usando o MoltenVK que vem no Wine Stable |
| O DXVK 1.10.3 não compila mais com o mingw-w64 do GCC 16 (falta `<cstdint>`, e dois remendos antigos conflitam com os headers) | O `build-graphics.sh` força `-include cstdint` e desativa os dois remendos |
| O DXVK recusa todos os níveis com o MoltenVK comum (sem geometry shaders) | O `build-graphics.sh` compila o MoltenVK da CodeWeavers, que oferece esse recurso |
| Os projetos do MoltenVK pedem macOS 10.15, que o Xcode 27 não aceita | Versão mínima elevada para 12.0 |

Ainda não se sabe qual patch da CodeWeavers conserta os lobbies. Os candidatos mais prováveis estão no código de rede (`nsiproxy`, `ws2_32`). Se você descobrir, abra uma issue.

## Licença e créditos

Os scripts deste repositório estão sob a licença MIT (veja [LICENSE](LICENSE)). O Wine compilado é LGPL-2.1 ou posterior, como o código da CodeWeavers de onde vem. As bibliotecas copiadas do Wine Stable.app mantêm as licenças delas.

- [Wine](https://www.winehq.org) e [CodeWeavers](https://www.codeweavers.com), pela publicação do código
- [Gcenx](https://github.com/Gcenx/macOS_Wine_builds), pelos builds de Wine para macOS em que este se baseia
- [notpop/steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) e o [fork do alexwinskii](https://github.com/alexwinskii/steam-on-m1-wine), por fazerem a Steam rodar no Wine 11
