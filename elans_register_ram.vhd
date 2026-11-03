library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity elans_register_ram is
    generic (
        depth : positive := 1024;
        address_width : positive := 10;
        data_width : positive := 1
    );
    port (
        clock_i : in std_logic;
        enable_i : in std_logic;
        write_i : in std_logic;
        address_i : in std_logic_vector(address_width - 1 downto 0);
        data_i : in std_logic_vector(data_width - 1 downto 0);
        data_o : out std_logic_vector(data_width - 1 downto 0)
    );
end entity;

architecture rtl of elans_register_ram is
    type ram_type is array (0 to depth - 1) of std_logic_vector(data_width - 1 downto 0);
    signal ram : ram_type;
begin
    ram_pr: process (clock_i) is
    begin
        if rising_edge(clock_i) then
            if enable_i = '1' then
                if write_i = '1' then
                    ram(to_integer(unsigned(address_i))) <= data_i;
                    data_o <= data_i;
                else
                    data_o <= ram(to_integer(unsigned(address_i)));
                end if;
            end if;
        end if;
    end process;
end architecture;
