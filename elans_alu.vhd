library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity elans_alu is
    generic (
        use_async_reset : boolean := true;
        use_sync_reset : boolean := true;
        async_reset_active : std_logic := '1';
        sync_reset_active : std_logic := '1' 
    );
    port (
        clock_i : in std_logic;
        async_reset_i : in std_logic;
        sync_reset_i : in std_logic;
        clear_i : in std_logic;
        step_i : in std_logic;
        subtract_i : in std_logic;
        operation_i : in std_logic_vector(2 downto 0);
        a_i : in std_logic;
        b_i : in std_logic;
        result_o : out std_logic;
        less_unsigned_o : out std_logic;
        equal_o : out std_logic
    );
end entity;
architecture rtl of elans_alu is
    signal carry_q : std_logic;
    signal equal_q : std_logic;
    signal b_bit : std_logic;
    signal sum_bit : std_logic;
    signal carry_next : std_logic;
begin
    b_bit <= b_i xor subtract_i;
    sum_bit <= a_i xor b_bit xor carry_q;
    carry_next <= (a_i and b_bit) or (a_i and carry_q) or (b_bit and carry_q);
    result_o <= (a_i and b_i) when operation_i = "111" else
                (a_i or b_i) when operation_i = "110" else
                (a_i xor b_i) when operation_i = "100" else sum_bit;
    less_unsigned_o <= not carry_q;
    equal_o <= equal_q;
    alu_pr: process (clock_i, async_reset_i) is
    begin
        if (async_reset_i = async_reset_active) and use_async_reset then
                carry_q <= '0';
                equal_q <= '1';
        elsif rising_edge(clock_i) then
            if (sync_reset_i = sync_reset_active) and use_sync_reset then
                carry_q <= '0';
                equal_q <= '1';
            else
                if clear_i = '1' then
                    carry_q <= subtract_i;
                    equal_q <= '1';
                elsif step_i = '1' then
                    carry_q <= carry_next;
                    equal_q <= equal_q and not (a_i xor b_i);
                end if;
            end if;
        end if;
    end process;
end architecture;
