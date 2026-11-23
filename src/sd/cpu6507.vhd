-- cpu6507.vhd : cpu65xx with plain ports (instantiated from Verilog)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity cpu6507 is
  port (clk, enable, reset : in std_logic;
        di   : in  std_logic_vector(7 downto 0);
        dq   : out std_logic_vector(7 downto 0);
        addr : out std_logic_vector(15 downto 0);
        we   : out std_logic);
end entity;
architecture rtl of cpu6507 is
  signal a : unsigned(15 downto 0);
  signal o : unsigned(7 downto 0);
begin
  addr <= std_logic_vector(a);
  dq   <= std_logic_vector(o);
  cpu : entity work.cpu65xx
    generic map (pipelineOpcode => false, pipelineAluMux => false, pipelineAluOut => false)
    port map (clk => clk, enable => enable, reset => reset, nmi_n => '1', irq_n => '1', so_n => '1',
      di => unsigned(di), do => o, addr => a, we => we,
      debugOpcode => open, debugPc => open, debugA => open, debugX => open,
      debugY => open, debugS => open);
end architecture;
