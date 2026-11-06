library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity elans_inter is
    port (
        instruction_i : in std_logic_vector(31 downto 0);
        bit_i : in unsigned(4 downto 0);
        opcode_i : in std_logic_vector(6 downto 0);
        is_lui_i : in std_logic;
        is_auipc_i : in std_logic;
        is_branch_i : in std_logic;
        is_store_i : in std_logic;
        immediate_bit_o : out std_logic
    );
end entity;

architecture rtl of elans_inter is
    subtype instruction_bit_index_type is std_logic_vector(4 downto 0);
    type immediate_index_table_type is array (0 to 31) of instruction_bit_index_type;
    constant immediate_i_indices : immediate_index_table_type := (
        "10100", "10101", "10110", "10111", "11000", "11001", "11010", "11011",
        "11100", "11101", "11110", "11111", "11111", "11111", "11111", "11111",
        "11111", "11111", "11111", "11111", "11111", "11111", "11111", "11111",
        "11111", "11111", "11111", "11111", "11111", "11111", "11111", "11111"
    );
    constant immediate_s_indices : immediate_index_table_type := (
        "00111", "01000", "01001", "01010", "01011", "11001", "11010", "11011",
        "11100", "11101", "11110", "11111", "11111", "11111", "11111", "11111",
        "11111", "11111", "11111", "11111", "11111", "11111", "11111", "11111",
        "11111", "11111", "11111", "11111", "11111", "11111", "11111", "11111"
    );
    constant immediate_b_indices : immediate_index_table_type := (
        "11111", "01000", "01001", "01010", "01011", "11001", "11010", "11011",
        "11100", "11101", "11110", "00111", "11111", "11111", "11111", "11111",
        "11111", "11111", "11111", "11111", "11111", "11111", "11111", "11111",
        "11111", "11111", "11111", "11111", "11111", "11111", "11111", "11111"
    );
    constant immediate_j_indices : immediate_index_table_type := (
        "11111", "10101", "10110", "10111", "11000", "11001", "11010", "11011",
        "11100", "11101", "11110", "10100", "01100", "01101", "01110", "01111",
        "10000", "10001", "10010", "10011", "11111", "11111", "11111", "11111",
        "11111", "11111", "11111", "11111", "11111", "11111", "11111", "11111"
    );
    signal immediate_index : instruction_bit_index_type;
    signal immediate_zero : std_logic;
begin
    -- Select a 5-bit source index before reading instruction_i. This
    -- avoids a format multiplexer spread over a 32-bit immediate word.
    -- Sign extension maps to bit 31; only format-specific zeros need masking.
    immediate_index <= std_logic_vector(bit_i) when is_lui_i = '1' or is_auipc_i = '1' else
        immediate_j_indices(to_integer(bit_i)) when opcode_i = "1101111" else
        immediate_b_indices(to_integer(bit_i)) when is_branch_i = '1' else
        immediate_s_indices(to_integer(bit_i)) when is_store_i = '1' else
        immediate_i_indices(to_integer(bit_i));
    immediate_zero <= '1' when
        ((is_lui_i = '1' or is_auipc_i = '1') and bit_i < 12) or
        ((is_branch_i = '1' or opcode_i = "1101111") and bit_i = 0) else '0';
    immediate_bit_o <= '0' when immediate_zero = '1' else
        instruction_i(to_integer(unsigned(immediate_index)));
end architecture;
