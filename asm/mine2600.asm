; ============================================================================
;  MINE 2600
;  Initial Test Build 2  --  "ITB2 / BLOCO PRETO NO CENTRO"
;  ---------------------------------------------------------------------------
;  Plataformas : Atari Video Computer System (2600), MOS 6507, 1,19 MHz
;  Formato     : cartucho de 2 KB (2048 bytes)
;  Alvo        : Stella / Javatari
;  O que tem   : o ceu azul $9E do ITB1 + um bloco preto $00 no centro da tela
;  O que NAO   : sem jogador, sem mundo, sem colisao, sem HUD, sem audio.
;                O bloco e estatico: nao e um objeto do jogo ainda, e a
;                primeira prova de que o renderizador escreve na TIA na hora
;                certa.
;
;  Herancas do ITB1
;  -----------------
;    * cartucho de 2 KB, vetores em $FFFC/$FFFE
;    * paleta escrita dentro do VBLANK
;    * loop de quadro canonico (VSYNC -> VBLANK -> visivel -> 37 linhas)
;    * as 7 cores, exceto COLUPF, continuam em $9E
;
;  O truque do build
;  -----------------
;  Em modo "4 color clocks" (CTRLPF = %11) so os 10 primeiros bits do
;  playfield cabem na linha de 40 color clocks:
;
;       PF0 (4 bits)   PF1 (4 bits)   PF2 (2 bits)
;      |------------|------------|--------|
;      0            10           20        40 color clocks
;                             ^^^^^
;                      o centro exato da tela
;
;  Ou seja: os 2 bits mais baixos do PF2 sao, por construcao, os 2 pixels
;  centrais da linha. Pior que ficar bonito: e barato (2 escritas por
;  mudanca de linha) e nao depende de nenhum ciclo critico.
; ============================================================================

    processor 6502
    include "includes/vcs.inc"

; ---------------------------------------------------------------------------
;  Identificacao
; ---------------------------------------------------------------------------
BUILD_ID      = 2
BUILD_NOME    = "ITB2 - BLOCO PRETO NO CENTRO"

; ---------------------------------------------------------------------------
;  Paleta -- indices de 4 bits no espaco NTSC (1 nybble = matiz,
;  1 nybble = luminancia). O mesmo numero muda de cor conforme o controle
;  de matiz do TV, entao estes valores sao a paleta FIXA do projeto.
; ---------------------------------------------------------------------------
SKY_COL       = SKY        ; $9E  azul de ceu
BLOCO_COL     = $00        ; $00  preto do bloco

; ---------------------------------------------------------------------------
;  Geometria do quadro
;
;  262 linhas (NTSC):
;      linhas   0..  2  -> VSYNC
;      linhas   3.. 39  -> VBLANK (37)
;      linhas  40..261  -> visivel (222)
;
;  O laco canonico spends as ultimas 37 linhas so em WSYNC, entao o
;  renderizador realmente controla as 185 linhas do meio:
;      40 .. 224
;
;  O bloco e desenhado em ALTURA_BLOCO linhas dentro dessa faixa, e as
;  linhas de ceu acima/abaixo sao o que sobra. 74 + 36 + 75 = 185.
;
;  1 color clock equivale, na tela, a aproximadamente 6 linhas de video.
;  O bloco tem 8 color clocks de largura (2 bits de 4 clks), entao
;  8 * 6 = 48 linhas seria o "quadrado perfeito"; usamos 36, que ja
;  parece um cubo sem virar um muro preto.
; ---------------------------------------------------------------------------
ALTURA_BLOCO  = 36         ; altura do bloco, em linhas
ACIMA_BLOCO   = 74         ; linhas de ceu antes do bloco
ABAIXO_BLOCO  = 75         ; linhas de ceu depois do bloco

; ---------------------------------------------------------------------------
;  O bloco em si
;  %00000011 -> os 2 bits centrais do playfield (8 color clocks de largura)
; ---------------------------------------------------------------------------
BLOCO_BITS    = %00000011

; ---------------------------------------------------------------------------
;  RESET -- $F800 (janela de 2 KB do cartucho)
; ---------------------------------------------------------------------------
    org $F800

Reset:
    SEI                     ; sem IRQ do RIOT: a CPU e 100% do jogo
    CLD                     ; sem modo decimal
    LDX #$FF
    TXS                     ; pilha em $FF

    ; Zera os 128 bytes de RAM de verdade ($80-$FF).
    ; NAO se usa "STA $00,X": no 6507 os enderecos $00-$7F NAO sao RAM, sao
    ; espelhos dos registros do TIA/RIOT. Limpar por ali escreveria em
    ; VSYNC, VBLANK, WSYNC... e ainda custaria ciclos de espera.
    ; O indice vai de $7F ate $00, entao $80+X nunca passa de $FF e nunca
    ; envolve o espelho de hardware.
    LDA #0
    LDX #$7F
ClearRAM:
    STA $80,X               ; $80 + X = $80..$FF
    DEX
    BPL ClearRAM

    ; 1 player (desliga o placar do console) + playfield em 4 color clocks.
    ; O tamanho do playfield e uma propriedade estatica: fica escrito uma vez.
    LDA #CTRLPF_SKY_4CLK
    STA CTRLPF

    ; Aguarda o primeiro VBLANK. Em cold start os registros do TIA nao tem
    ; valor definido; escrever a paleta antes do VBLANK pode piscar uma
    ; cor aleatoria por um quadro. Custa microssegundos. Faz certo.
WaitFirstVBL:
    LDA VBLANK
    BPL WaitFirstVBL        ; bit7 = 0 => ainda estao desenhando

    ; ---- Paleta ----------------------------------------------------------
    ; COLUBK pinta o ceu: e a cor de tudo que o playfield deixa apagado.
    ; COLUPF pinta os "accesos" do playfield: e a cor do bloco.
    LDA #SKY_COL
    STA COLUBK              ; ceu
    STA COLUP0              ; os sprites ficam com a cor do ceu...
    STA COLUP1              ; ...e por isso somem completamente
    STA COLUM0
    STA COLUM1
    STA COLBL
    LDA #BLOCO_COL
    STA COLUPF              ; o bloco preto
    LDA #0
    STA $00                 ; solta o latch de endereco espelhado

    ; Zera os registradores de grafico: evita qualquer residuo caso o
    ; emulador/console ja tenha executado outro cartucho.
    LDA #0
    STA PF0
    STA PF1
    STA PF2
    STA GRP0
    STA GRP1
    STA ENAM0
    STA ENAM1
    STA ENABL
    STA $00

; ---------------------------------------------------------------------------
;  Frame -- o coracao do 2600
;  262 linhas por quadro (NTSC). 60 quadros por segundo, sempre.
; ---------------------------------------------------------------------------
Frame:
    ; ---- 3 linhas de VSYNC ------------------------------------------------
    LDA #0
    STA VSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC               ; 3 linhas de VSYNC + 4 ate alinhar com a linha 0
    STA WSYNC
    STA WSYNC
    STA WSYNC

    ; ---- Inicia o VBLANK (2 linhas) ---------------------------------------
    LDA #%00000010
    STA VBLANK

    ; >>> AQUI ENTRA O SETUP DO QUADRO (camera, visao, HUD, fisica) <<<

    ; ---- Encerra o VBLANK: a TIA volta a desenhar a linha 0 ---------------
    LDA #0
    STA VBLANK

    ; ---- CEU: as 74 linhas acima do bloco -------------------------------
    ; PF2 = 0 deixa a linha mostrar COLUBK. A = 0 tambem serve de valor
    ; para o "STA WSYNC" do laco (o valor de WSYNC e ignorado).
    LDA #0
    STA PF2
    LDX #ACIMA_BLOCO
CeuAcima:
    STA WSYNC
    DEX
    BNE CeuAcima            ; 4 + 2 + 3 = 9 ciclos por linha, longe dos 228

    ; ---- BLOCO: 36 linhas pretas no centro --------------------------------
    ; A mudanca de PF2 so vale a partir da PROXIMA linha, por isso o bloco
    ; comeca uma linha depois do ultimo WSYNC acima. E o que faz o topo dele.
    LDA #BLOCO_BITS
    STA PF2
    LDX #ALTURA_BLOCO
Bloco:
    STA WSYNC
    DEX
    BNE Bloco

    ; ---- CEU: as 75 linhas de baixo --------------------------------------
    LDA #0
    STA PF2
    LDX #ABAIXO_BLOCO
CeuAbaixo:
    STA WSYNC
    DEX
    BNE CeuAbaixo

    ; ---- 37 linhas de fechamento do quadro -------------------------------
    ; Sao as 37 ultimas linhas antes do proximo VSYNC. Nada e desenhado
    ; aqui de proposito: e a margem que o 2600 sempre deixa no fim do quadro.
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC
    STA WSYNC

    JMP Frame               ; e o comeco do proximo quadro

; ---------------------------------------------------------------------------
;  Tratador de IRQ/BRK
;  Morto no ITB2: o RESET roda SEI e nada nunca religa as interrupcoes.
;  Existe para o cartucho fechar em 2048 bytes e para uma IRQ inesperada
;  nao saltar para o meio dos registradores da TIA.
; ---------------------------------------------------------------------------
IrqHandler:
    SEI
    RTI

; ---------------------------------------------------------------------------
;  Vetores do cartucho (2 KB -> $FFFC, espelhado em $1FFC)
;  RESET = $F800 | IRQ/BRK = apontador acima
;  Esses 4 bytes sao o que fecha o arquivo em exatamente 2048.
; ---------------------------------------------------------------------------
    org $FFFC
    .word Reset
    .word IrqHandler

; ---------------------------------------------------------------------------
    END
