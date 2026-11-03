library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity elans_register_file is
    generic (
        use_async_reset : boolean := true;
        use_sync_reset : boolean := true;
        async_reset_active : std_logic := '1';
        sync_reset_active : std_logic := '1' ;
        organization : string := "a"
    );
    port (
        clock_i : in std_logic;
        async_reset_i : in std_logic;
        sync_reset_i : in std_logic;
        request_i : in std_logic;
        write_i : in std_logic;
        index_i : in std_logic_vector(4 downto 0);
        data_i : in std_logic_vector(31 downto 0);
        ready_o : out std_logic;
        done_o : out std_logic;
        data_o : out std_logic_vector(31 downto 0)
    );
end entity;
architecture rtl of elans_register_file is
    type state_type is (idle, access_ram, capture, complete);
    signal state_q : state_type;
    signal index_q : std_logic_vector(4 downto 0);
    signal bit_q : unsigned(4 downto 0);
    signal write_q : std_logic;
    signal word_q : std_logic_vector(31 downto 0);
    signal read_q : std_logic_vector(31 downto 0);
    signal ram_enable : std_logic;
    signal ram_write : std_logic;
    signal ram_bit_data : std_logic_vector(0 downto 0);
    signal ram_result : std_logic_vector(31 downto 0);
begin
    assert organization = "a" or organization = "b" report "invalid RF organization" severity failure;
    ready_o <= '1' when state_q = idle else '0';
    done_o <= '1' when state_q = complete else '0';
    data_o <= read_q;
    ram_enable <= '1' when state_q = access_ram and index_q /= "00000" else '0';
    ram_write <= write_q;
    ram_bit_data(0) <= word_q(to_integer(bit_q));
    bits_gen: if organization = "a" generate
        signal ram_address : std_logic_vector(12 downto 0);
    begin
        ram_address <= "000" & index_q & std_logic_vector(bit_q);
        ram_inst: entity work.elans_register_ram
            generic map (depth => 8192, address_width => 13, data_width => 1)
            port map (clock_i => clock_i, enable_i => ram_enable, write_i => ram_write,
                      address_i => ram_address, data_i => ram_bit_data,
                      data_o => ram_result(0 downto 0));
        ram_result(31 downto 1) <= (others => '0');
    end generate;
    words_gen: if organization = "b" generate
        signal ram_address : std_logic_vector(7 downto 0);
    begin
        ram_address <= "000" & index_q;
        ram_inst: entity work.elans_register_ram
            generic map (depth => 256, address_width => 8, data_width => 32)
            port map (clock_i => clock_i, enable_i => ram_enable, write_i => ram_write,
                      address_i => ram_address, data_i => word_q,
                      data_o => ram_result);
    end generate;
    rf_pr: process (clock_i, async_reset_i) is
    begin
        if (async_reset_i = async_reset_active) and use_async_reset then
                state_q <= idle;
                index_q <= (others => '0');
                bit_q <= (others => '0');
                write_q <= '0';
                word_q <= (others => '0');
                read_q <= (others => '0');
        elsif rising_edge(clock_i) then
            if (sync_reset_i = sync_reset_active) and use_sync_reset then
                state_q <= idle;
                index_q <= (others => '0');
                bit_q <= (others => '0');
                write_q <= '0';
                word_q <= (others => '0');
                read_q <= (others => '0');
            else
                if state_q = idle then
                    if request_i = '1' then
                        index_q <= index_i;
                        write_q <= write_i;
                        word_q <= data_i;
                        bit_q <= (others => '0');
                        state_q <= access_ram;
                    end if;
                elsif state_q = access_ram then
                    state_q <= capture;
                elsif state_q = capture then
                    if index_q = "00000" then
                        read_q <= (others => '0');
                        state_q <= complete;
                    elsif organization = "b" then
                        read_q <= ram_result;
                        state_q <= complete;
                    else
                        read_q(to_integer(bit_q)) <= ram_result(0);
                        if bit_q = 31 then
                            state_q <= complete;
                        else
                            bit_q <= bit_q + 1;
                            state_q <= access_ram;
                        end if;
                    end if;
                elsif state_q = complete then
                    state_q <= idle;
                end if;
            end if;
        end if;
    end process;
end architecture;
