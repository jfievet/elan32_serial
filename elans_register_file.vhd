library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- A transaction transfers 32 bits, least significant bit first.
-- request_i is accepted when ready_o is high. Each bit is transferred
-- on valid/ready; done_o follows the final bit (and the RAM write in mode b).
entity elans_register_file is
    generic (
        use_async_reset : boolean := true;
        use_sync_reset : boolean := true;
        async_reset_active : std_logic := '1';
        sync_reset_active : std_logic := '1';
        organization : string := "a"
    );
    port (
        clock_i : in std_logic;
        async_reset_i : in std_logic;
        sync_reset_i : in std_logic;
        cancel_i : in std_logic;
        request_i : in std_logic;
        write_i : in std_logic;
        index_i : in std_logic_vector(4 downto 0);
        data_i : in std_logic;
        bit_valid_i : in std_logic;
        bit_ready_o : out std_logic;
        data_o : out std_logic;
        bit_valid_o : out std_logic;
        bit_ready_i : in std_logic;
        ready_o : out std_logic;
        done_o : out std_logic
    );
end entity;

architecture rtl of elans_register_file is
    type state_type is (idle, read_access, read_capture, read_stream,
                        write_stream, write_access, complete);
    signal state_q : state_type;
    signal index_q : std_logic_vector(4 downto 0);
    signal bit_q : unsigned(4 downto 0);
    signal word_q : std_logic_vector(31 downto 0);
    signal ram_enable : std_logic;
    signal ram_write : std_logic;
    signal ram_result : std_logic_vector(31 downto 0);
begin
    assert organization = "a" or organization = "b"
        report "invalid RF organization" severity failure;
    ready_o <= '1' when state_q = idle else '0';
    done_o <= '1' when state_q = complete else '0';
    bit_ready_o <= '1' when state_q = write_stream and cancel_i = '0' else '0';
    bit_valid_o <= '1' when cancel_i = '0' and
        ((organization = "a" and state_q = read_capture) or state_q = read_stream) else '0';
    data_o <= '0' when index_q = "00000" else
              ram_result(0) when organization = "a" else word_q(0);
    ram_enable <= '1' when cancel_i = '0' and index_q /= "00000" and
        (state_q = read_access or state_q = write_access or
         (organization = "a" and state_q = write_stream and bit_valid_i = '1')) else '0';
    ram_write <= '1' when state_q = write_stream or state_q = write_access else '0';

    bits_gen: if organization = "a" generate
        signal ram_data : std_logic_vector(0 downto 0);
        signal ram_address : std_logic_vector(12 downto 0);
    begin
        ram_data(0) <= data_i;
        ram_address <= "000" & index_q & std_logic_vector(bit_q);
        ram_inst: entity work.elans_register_ram
            generic map (depth => 8192, address_width => 13, data_width => 1)
            port map (clock_i => clock_i, enable_i => ram_enable, write_i => ram_write,
                address_i => ram_address,
                data_i => ram_data, data_o => ram_result(0 downto 0));
        ram_result(31 downto 1) <= (others => '0');
    end generate;
    words_gen: if organization = "b" generate
        signal ram_address : std_logic_vector(7 downto 0);
    begin
        ram_address <= "000" & index_q;
        ram_inst: entity work.elans_register_ram
            generic map (depth => 256, address_width => 8, data_width => 32)
            port map (clock_i => clock_i, enable_i => ram_enable, write_i => ram_write,
                address_i => ram_address, data_i => word_q, data_o => ram_result);
    end generate;

    rf_pr: process (clock_i, async_reset_i) is
    begin
        if (async_reset_i = async_reset_active) and use_async_reset then
            state_q <= idle;
            index_q <= (others => '0');
            bit_q <= (others => '0');
            word_q <= (others => '0');
        elsif rising_edge(clock_i) then
            if (sync_reset_i = sync_reset_active) and use_sync_reset then
                state_q <= idle;
                index_q <= (others => '0');
                bit_q <= (others => '0');
                word_q <= (others => '0');
            elsif cancel_i = '1' then
                state_q <= idle;
            else
                case state_q is
                    when idle =>
                        if request_i = '1' then
                            index_q <= index_i;
                            bit_q <= (others => '0');
                            if write_i = '1' then
                                state_q <= write_stream;
                            else
                                state_q <= read_access;
                            end if;
                        end if;
                    when read_access =>
                        state_q <= read_capture;
                    when read_capture =>
                        if organization = "b" then
                            word_q <= ram_result;
                            state_q <= read_stream;
                        elsif bit_ready_i = '1' then
                            if bit_q = 31 then
                                state_q <= complete;
                            else
                                bit_q <= bit_q + 1;
                                state_q <= read_access;
                            end if;
                        end if;
                    when read_stream =>
                        if bit_ready_i = '1' then
                            word_q <= '0' & word_q(31 downto 1);
                            if bit_q = 31 then
                                state_q <= complete;
                            else
                                bit_q <= bit_q + 1;
                            end if;
                        end if;
                    when write_stream =>
                        if bit_valid_i = '1' then
                            if organization = "b" then
                                word_q <= data_i & word_q(31 downto 1);
                            end if;
                            if bit_q = 31 then
                                if organization = "b" then
                                    state_q <= write_access;
                                else
                                    state_q <= complete;
                                end if;
                            else
                                bit_q <= bit_q + 1;
                            end if;
                        end if;
                    when write_access =>
                        state_q <= complete;
                    when complete =>
                        state_q <= idle;
                end case;
            end if;
        end if;
    end process;
end architecture;
