library ieee;
use ieee.std_logic_1164.all;

entity aes_256_cyph_top is
    port (
        clk  : in std_logic;
        rst  : in std_logic
    );
end entity aes_256_cyph_top;

architecture rtl of aes_256_cyph_top is

    signal clkf : std_logic;
    signal clks : std_logic;
    signal locked : std_logic;

    signal data_i       : std_logic_vector(127 downto 0) := (others => '0');
    signal valid_i      : std_logic := '0';
    signal key_i        : std_logic_vector(255 downto 0) := (others => '0');
    signal key_valid    : std_logic := '0';
    signal key_ready_o  : std_logic;
    signal cyph_valid_o : std_logic;
    signal cyph_data_o  : std_logic_vector(127 downto 0);

    component clk_wiz_0
        port (
            clk_out1 : out std_logic;
            clk_out2 : out std_logic;
            locked   : out std_logic;
            clk_in1  : in  std_logic
        );
    end component;

    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of u_core : label is "TRUE";

begin

    pll : clk_wiz_0
        port map (
            clk_out1 => clkf,
            clk_out2 => clks,
            locked   => locked,
            clk_in1  => clk
        );

    u_core : entity work.aes_256_ciph_fp
        port map (
            clk   => clkf,
            --clk_cipher   => clkf,
            --clk_schedule => clks,
            rst          => rst,
            data_i       => data_i,
            data_valid_i      => valid_i,
            key_i        => key_i,
            key_valid_i    => key_valid,
            key_ready_o  => key_ready_o,
            ciph_valid_o => cyph_valid_o,
            ciph_data_o  => cyph_data_o
        );

end architecture rtl;