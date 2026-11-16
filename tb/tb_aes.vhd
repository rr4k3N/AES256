-----------------------------------------
--  Testbench for the pipelined AES-256
--  (entity aes_256_cyph_fast)
-----------------------------------------
-- Reference vectors : AES-256 ECB computed with an independent implementation
--                     (they include NIST SP 800-38A F.1.5 and FIPS-197 C.3).
--
-- Phase 0 : power-up, nothing must come out and key_ready must be low before a key is loaded
-- Phase 1 : 30 blocks back to back (streaming): right data, right order, 30 clocks in a row
-- Phase 2 : key change straight after a key was put in (second key_valid after 0,1,3,10,30,50 clocks,
--           then a triple re-key). The blocks must be encrypted with the LAST key.
-- Phase 3 : 16 key changes, each one right after the last block of the previous key came out
-- Phase 4 : INFORMATION ONLY - key change while blocks are still in the pipeline (not a supported
--           use, the result is just reported)
--
-- Convention: key_i must be held until the key_valid pulse has been sampled; this testbench clears it
-- right after the pulse (CLEAR_KEY_AFTER_PULSE) to prove that the design latches the key.

library ieee;
use ieee.std_logic_1164.all;

entity tb_aes is
end entity tb_aes;

architecture testbench of tb_aes is

  constant per                   : time    := 10 ns;    -- 100 MHz
  constant READY_TIMEOUT         : integer := 200;      -- clocks to wait for key_ready after a key load
  constant DRAIN_TIMEOUT         : integer := 200;      -- clocks to wait for outstanding outputs
  constant INFLIGHT_TEST         : boolean := true;     -- phase 4 (information only)
  constant CLEAR_KEY_AFTER_PULSE : boolean := true;

  -- ----------------------------------------------------------------
  -- test data
  -- ----------------------------------------------------------------
  type slv128_arr is array (natural range <>) of std_logic_vector(127 downto 0);
  type slv256_arr is array (natural range <>) of std_logic_vector(255 downto 0);

  constant NKEYS : integer := 8;
  type ct_table_t is array (0 to NKEYS-1, 0 to 3) of std_logic_vector(127 downto 0);

  -- keys: 0 = NIST SP 800-38A, 1 = FIPS-197 C.3, 2 = all zeros, 3 = all ones, 4..7 = random
  constant KEYS : slv256_arr(0 to NKEYS-1) := (
    X"603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4",
    X"000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F",
    X"0000000000000000000000000000000000000000000000000000000000000000",
    X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
    X"8F0FE05D3EF8A85AF4CB2C5B5E5381A1E64502A75B062BB8A5C3AFFDC2547B9D",
    X"A5B4CDA4DB9ABB244658B4D5C11393969D519CDAED294ED60294FBFBB4412D3F",
    X"C45AAE2FF94D1D64FE4E18C025265BE7CB273972970F03356C32053EE3EB9F76",
    X"B2FEBBCA0AE0F2BCD2993B07FC734A4867E792091914E00D95E7CD0C481EC3B7"
  );

  -- four plaintexts (the NIST blocks) and their ciphertext under every key: CT_TABLE(key, block)
  constant PT4 : slv128_arr(0 to 3) := (
    X"6BC1BEE22E409F96E93D7E117393172A",
    X"AE2D8A571E03AC9C9EB76FAC45AF8E51",
    X"30C81C46A35CE411E5FBC1191A0A52EF",
    X"F69F2445DF4F9B17AD2B417BE66C3710"
  );

  constant CT_TABLE : ct_table_t := (
    (X"F3EED1BDB5D2A03C064B5A7E3DB181F8", X"591CCB10D410ED26DC5BA74A31362870", X"B6ED21B99CA6F4F9F153E7B1BEAFED1D", X"23304B7A39F9F3FF067D8D8F9E24ECC7"),
    (X"E0A8F50EC76A04D5A96A175AA870EF63", X"542DDEA4D5FAAD623EF884CF4E198BDC", X"1FD0F38E35614ABF31CA51243550676B", X"27E3EE8DA6FB1F4C8431129D4E896A9D"),
    (X"377D5B7649605EFD9153AB716113D78F", X"1FB8D2BC3D8D5769CF535D77F9D43315", X"FF095D96C68D6AE1A78BDDEA2538E26C", X"FB224114AA709F164678DF110F000B78"),
    (X"024E9A6EE6E4AD2533017ABC56EB4CB7", X"35935FBCB9C691EBDBCF46E3FF01869C", X"B69D74CD439DDB1A06515273C82345D3", X"E4CFEA3DA2457939AA6F9863B41E9ECC"),
    (X"662FF5906CF08C4932F02ABA962EF663", X"DDF758D86C443A6D01C63037AFC9EF5C", X"28B93398AC29F3C93B0441B2D45F8532", X"38CECB9392DF161CC8ABF6B144D77556"),
    (X"9DDD509C9A8B671D2F3C256AA6ACDC89", X"7A666CD4A7096BA64C15373E6F5F740A", X"87FD053B30CA4CD8AE6AB91AF6D4BD89", X"C041FC24AC542B574FEAD18050FAA2EF"),
    (X"13A1EC8FFDAAF437F47CB616A5A7EC44", X"E6347E74BE56571E02D9AE356481915A", X"5C9D505E794BB8FD7820A2A4E9A3B87A", X"7BDB65273CC12C0B523B03938822334C"),
    (X"2E216382E08C400AAC64D3B50D9DFC21", X"64D9611816FA2BD395407AEDDAAA786C", X"2FD361C0E901868EA8553644F6261A25", X"4F1218533C78B25C47D29FFB732BE718")
  );

  -- 30 blocks for the streaming test, encrypted with KEYS(0)
  constant STREAM_PT : slv128_arr(0 to 29) := (
    X"6BC1BEE22E409F96E93D7E117393172A",
    X"AE2D8A571E03AC9C9EB76FAC45AF8E51",
    X"30C81C46A35CE411E5FBC1191A0A52EF",
    X"F69F2445DF4F9B17AD2B417BE66C3710",
    X"00000000000000000000000000000000",
    X"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
    X"000102030405060708090A0B0C0D0E0F",
    X"F0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF",
    X"00000101010101010101010101010102",
    X"00000202020202020202020202020204",
    X"00000303030303030303030303030306",
    X"00000404040404040404040404040408",
    X"0000050505050505050505050505050A",
    X"0000060606060606060606060606060C",
    X"F37764F337B5B9D6EBDABAF5F8F0F041",
    X"B4E604E4922C0AFDB593B7BBE1C7C1F7",
    X"BD3D45629C393DDCD8AF60EA8625ECEE",
    X"D9C9CCF48ADF59D8743FAA7FE97376D2",
    X"9B58CFD4CC7DDFBFA5DBB422E895C6C5",
    X"EC2C75F61CE912C40ADEEDB17B0C6AC1",
    X"DA30DA31577ED2AEEF225CDDA0E53D9D",
    X"F66FFB8CF21019F1B1D3711F683CBDCD",
    X"3343CCA2A6B7709597568833202CD72F",
    X"666D6BDAC3D2BB55D9280A4D1E3001F6",
    X"D785BFF740BA75AAC8AD915247CEFD31",
    X"D3B885364D093331C2EB1A60699845BE",
    X"AB2B401EFF9619B4BABE537E8EEBD7EB",
    X"73460C1561AE29AD3A0917486F2D6763",
    X"98152979BDEF69F890C5FCE753CEE9E5",
    X"C8ECC80CC750907B4BFA045BE2E26AD8"
  );

  constant STREAM_CT : slv128_arr(0 to 29) := (
    X"F3EED1BDB5D2A03C064B5A7E3DB181F8",
    X"591CCB10D410ED26DC5BA74A31362870",
    X"B6ED21B99CA6F4F9F153E7B1BEAFED1D",
    X"23304B7A39F9F3FF067D8D8F9E24ECC7",
    X"E568F68194CF76D6174D4CC04310A854",
    X"3B3C2921C85A24DE9AC606CE6D1D60CC",
    X"B7BF3A5DF43989DD97F0FA97EBCE2F4A",
    X"0BDF7DF1591716335E9A8B15C860C502",
    X"52AD2E27080D431BCBBFDD0B2DA75D2A",
    X"6DCEA4AB77B0289B492A504C81F6CD12",
    X"3EA1CF3ACF4CD9A5C1030BD23292EDED",
    X"333FDD8B716478E30859E93A9CD79015",
    X"45938795116077C2A57694718A2621BA",
    X"E698D2E9DAFD5B5152151F7E6106CCAA",
    X"ECE8398A110A74E7B0D3FD978E499C0B",
    X"EED086F4CFBB2CA761E64B770130055A",
    X"B1428C3844ED52D2B5A626AEC74F7EAA",
    X"4DBAFC1388C0A9CCF9F25794594F87E9",
    X"76DE57AB95C457FE130286E4D7E1393C",
    X"E8F1943AAE9B9C6FAD7346D3E344E376",
    X"FBB7EF09CD6F9A4BCC1F89B301233F0E",
    X"CC226631CB3D166B47AB6308B81C1AC1",
    X"6108CAD2F97AC83A01BFEF1BD2619016",
    X"11D36B87BF18A466A57CB077D46955FB",
    X"A6949F7B40C41C8B5F4E8CA92F02FC88",
    X"06404DDD1DCB8B9E2514D52945278836",
    X"A6CC984F8A4E0CE8D12B11DE9D690535",
    X"0F804D61C74E44E693A0647742E83700",
    X"4E474E3AA1B8A9F9BE61ED8E07E1634F",
    X"CDB35532065F81FAF1E3A229DD933793"
  );

  -- ----------------------------------------------------------------
  -- signals
  -- ----------------------------------------------------------------
  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';
  signal data_i       : std_logic_vector(127 downto 0) := (others => '0');
  signal valid_i      : std_logic := '0';
  signal key_i        : std_logic_vector(255 downto 0) := (others => '0');
  signal key_valid    : std_logic := '0';
  signal key_ready    : std_logic := '0';
  signal cyph_valid_o : std_logic;
  signal cyph_data_o  : std_logic_vector(127 downto 0);

  constant MAXQ : integer := 256;
  signal exp_q      : slv128_arr(0 to MAXQ-1) := (others => (others => '0'));   -- expected output k
  signal alt_q      : slv128_arr(0 to MAXQ-1) := (others => (others => '0'));   -- alternative (phase 4)
  signal n_pushed   : integer := 0;      -- written by the stimulus
  signal n_checked  : integer := 0;      -- written by the checker
  signal n_errors   : integer := 0;
  signal n_total    : integer := 0;      -- valid outputs that were compared
  signal max_run    : integer := 0;      -- longest run of consecutive valid outputs
  signal info_mode  : boolean := false;
  signal info_x, info_y, info_bad : integer := 0;
  signal phase      : integer := 0;
  signal resync_idx : integer := 0;
  signal resync_tog : std_logic := '0';

  signal finished   : boolean := false;
  signal done       : boolean := false;

begin

  -- clock, stops when done so that "run -all" terminates
  clk_gen : process
  begin
    while not done loop
      clk <= '0';
      wait for per/2;
      clk <= '1';
      wait for per/2;
    end loop;
    wait;
  end process clk_gen;

  -- watchdog
  watchdog : process
  begin
    wait until finished for 500 us;
    if not finished then
      report "TIMEOUT: the testbench did not finish" severity error;
    end if;
    done <= true;
    wait;
  end process watchdog;

  -- ----------------------------------------------------------------
  -- stimulus
  -- ----------------------------------------------------------------
  stim : process

    variable pushed  : integer := 0;
    variable tb_errs : integer := 0;
    variable gap, ka, kb, kid, nb : integer;
    variable seen, drops          : integer;

    procedure tick (n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure tick;

    -- register the expected output of the next block (alt = value to classify against in phase 4)
    procedure push (ct : std_logic_vector(127 downto 0); alt : std_logic_vector(127 downto 0)) is
    begin
      exp_q(pushed) <= ct;
      alt_q(pushed) <= alt;
      pushed   := pushed + 1;
      n_pushed <= pushed;
    end procedure push;

    procedure send (pt : std_logic_vector(127 downto 0); ct : std_logic_vector(127 downto 0)) is
    begin
      push(ct, ct);
      data_i  <= pt;
      valid_i <= '1';
      tick(1);
    end procedure send;

    procedure idle is
    begin
      valid_i <= '0';
      data_i  <= (others => '0');
    end procedure idle;

    -- one key_valid pulse, one clock wide
    procedure pulse_key (k : std_logic_vector(255 downto 0)) is
    begin
      key_i     <= k;
      key_valid <= '1';
      tick(1);
      key_valid <= '0';
      if CLEAR_KEY_AFTER_PULSE then
        key_i <= (others => '0');
      end if;
    end procedure pulse_key;

    -- pulse, then wait for key_ready (it must drop after the pulse and come back)
    procedure load_key (k : std_logic_vector(255 downto 0)) is
      variable n : integer := 0;
    begin
      pulse_key(k);
      tick(1);
      if key_ready = '1' then
        report "key_ready is still high one clock after key_valid (stale ready), phase " & integer'image(phase)
          severity error;
        tb_errs := tb_errs + 1;
      end if;
      while key_ready /= '1' and n < READY_TIMEOUT loop
        tick(1);
        n := n + 1;
      end loop;
      if key_ready /= '1' then
        report "TIMEOUT: key_ready never came back, phase " & integer'image(phase) severity error;
        tb_errs := tb_errs + 1;
      end if;
    end procedure load_key;

    -- wait until every expected output has been checked; on timeout tell the checker to skip the rest
    procedure drain (report_timeout : boolean) is
      variable g : integer := 0;
    begin
      while n_checked < pushed and g < DRAIN_TIMEOUT loop
        tick(1);
        g := g + 1;
      end loop;
      if n_checked < pushed then
        if report_timeout then
          report "TIMEOUT: " & integer'image(pushed - n_checked) & " output(s) never arrived, phase "
                 & integer'image(phase) severity error;
          tb_errs := tb_errs + 1;
        end if;
        resync_idx <= pushed;
        resync_tog <= not resync_tog;
        tick(2);
      end if;
    end procedure drain;

  begin
    -- reset
    rst <= '1';
    tick(3);
    wait until falling_edge(clk);
    rst <= '0';
    tick(2);

    ----------------------------------------------------------------
    -- phase 0 : power-up behaviour
    ----------------------------------------------------------------
    phase <= 0;
    tick(100);
    if key_ready = '1' then
      report "key_ready is high before any key was loaded" severity error;
      tb_errs := tb_errs + 1;
    end if;

    ----------------------------------------------------------------
    -- phase 1 : 30 blocks back to back
    ----------------------------------------------------------------
    phase <= 1;
    load_key(KEYS(0));
    for i in 0 to 29 loop
      send(STREAM_PT(i), STREAM_CT(i));            -- one block per clock, valid_i stays high
    end loop;
    idle;
    drain(true);
    if max_run /= 30 then
      report "streaming: outputs were not on 30 consecutive clocks (longest run = " & integer'image(max_run) & ")"
        severity error;
      tb_errs := tb_errs + 1;
    end if;

    ----------------------------------------------------------------
    -- phase 2 : key change straight after a key was put in
    ----------------------------------------------------------------
    phase <= 2;
    for g in 0 to 5 loop
      case g is
        when 0      => gap := 0;
        when 1      => gap := 1;
        when 2      => gap := 3;
        when 3      => gap := 10;
        when 4      => gap := 30;
        when others => gap := 50;
      end case;
      ka := g mod NKEYS;
      kb := (g + 3) mod NKEYS;
      pulse_key(KEYS(ka));                         -- first key ...
      tick(gap);
      load_key(KEYS(kb));                          -- ... replaced by the second one before it was ready
      send(PT4(0), CT_TABLE(kb, 0));
      send(PT4(1), CT_TABLE(kb, 1));
      idle;
      drain(true);
    end loop;

    -- triple re-key: only the last key may count
    pulse_key(KEYS(4));
    tick(1);
    pulse_key(KEYS(5));
    tick(5);
    load_key(KEYS(6));
    send(PT4(2), CT_TABLE(6, 2));
    send(PT4(3), CT_TABLE(6, 3));
    idle;
    drain(true);

    ----------------------------------------------------------------
    -- phase 3 : key change right after the previous key was processed
    ----------------------------------------------------------------
    phase <= 3;
    for k in 0 to 15 loop
      kid := (k * 3) mod NKEYS;
      nb  := 1 + (k mod 4);
      load_key(KEYS(kid));
      for b in 0 to nb - 1 loop
        send(PT4(b), CT_TABLE(kid, b));
      end loop;
      idle;
      drain(true);                                 -- the next key_valid comes on the very next clock
    end loop;

    ----------------------------------------------------------------
    -- phase 4 : information only - key change while blocks are in flight
    ----------------------------------------------------------------
    if INFLIGHT_TEST then
      phase <= 4;
      load_key(KEYS(0));
      info_mode <= true;
      seen := n_checked;
      for b in 0 to 3 loop
        push(CT_TABLE(0, b), CT_TABLE(1, b));      -- expected with the old key / alternative with the new key
        data_i  <= PT4(b);
        valid_i <= '1';
        tick(1);
      end loop;
      idle;
      pulse_key(KEYS(1));                          -- new key while the blocks are still inside
      drain(false);
      info_mode <= false;
      tick(2);
      drops := 4 - (info_x + info_y + info_bad);
      report "INFO in-flight key change (4 blocks): " & integer'image(info_x) & " correct with the old key, "
             & integer'image(info_y) & " correct with the new key, " & integer'image(info_bad) & " corrupted, "
             & integer'image(drops) & " dropped (not an error)";
      -- the design must work again with the new key
      load_key(KEYS(1));
      send(PT4(0), CT_TABLE(1, 0));
      idle;
      drain(true);
    end if;

    ----------------------------------------------------------------
    -- verdict
    ----------------------------------------------------------------
    tick(5);
    if n_errors = 0 and tb_errs = 0 then
      report "All tests succeeded (" & integer'image(n_total) & " outputs compared)";
    else
      report "TESTS FAILED: " & integer'image(n_errors) & " wrong/unexpected outputs, "
             & integer'image(tb_errs) & " protocol errors" severity error;
    end if;

    finished <= true;
    wait;
  end process stim;

  -- ----------------------------------------------------------------
  -- checker: samples every valid output on the falling edge
  -- ----------------------------------------------------------------
  check : process (clk)
    variable idx      : integer := 0;
    variable errs     : integer := 0;
    variable run      : integer := 0;
    variable best_run : integer := 0;
    variable ix, iy, ib : integer := 0;
    variable total    : integer := 0;
    variable last_tog : std_logic := '0';
  begin
    if falling_edge(clk) then

      if resync_tog /= last_tog then               -- the stimulus gave up on missing outputs
        idx      := resync_idx;
        last_tog := resync_tog;
      end if;

      if cyph_valid_o = '1' then
        run := run + 1;
        if run > best_run then
          best_run := run;
        end if;

        if idx >= n_pushed then
          report "UNEXPECTED valid output (nothing was sent), phase " & integer'image(phase) severity error;
          errs := errs + 1;
        else
          if info_mode then
            if cyph_data_o = exp_q(idx) then
              ix := ix + 1;
            elsif cyph_data_o = alt_q(idx) then
              iy := iy + 1;
            else
              ib := ib + 1;
            end if;
          elsif cyph_data_o /= exp_q(idx) then
            report "output " & integer'image(idx) & " MISMATCH, phase " & integer'image(phase) severity error;
            errs := errs + 1;
          end if;
          idx   := idx + 1;
          total := total + 1;
        end if;
      else
        run := 0;
      end if;

      n_checked <= idx;
      n_errors  <= errs;
      n_total   <= total;
      max_run   <= best_run;
      info_x    <= ix;
      info_y    <= iy;
      info_bad  <= ib;
    end if;
  end process check;

  -- device under test
  dut : entity work.aes_256_ciph_fp
    port map (
      clk          => clk,
      rst          => rst,
      data_i       => data_i,
      data_valid_i      => valid_i,
      key_i        => key_i,
      key_valid_i    => key_valid,
      key_ready_o  => key_ready,
      ciph_valid_o => cyph_valid_o,
      ciph_data_o  => cyph_data_o
    );

end architecture testbench;
