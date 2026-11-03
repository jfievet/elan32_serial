library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity elans_core is
    generic (
        use_async_reset : boolean := true;
        use_sync_reset : boolean := true;
        async_reset_active : std_logic := '1';
        sync_reset_active : std_logic := '1' ;
        reset_pc : std_logic_vector(31 downto 0) := x"00000000";
        rf_organization : string := "a"
    );
    port (
        clock_i : in std_logic;
        async_reset_i : in std_logic;
        sync_reset_i : in std_logic;
        fault_i : in std_logic;
        fault_o : out std_logic;
        pc_o : out std_logic_vector(31 downto 0);
        previous_pc_o : out std_logic_vector(31 downto 0);
        debug_request_i : in std_logic;
        debug_index_i : in std_logic_vector(4 downto 0);
        debug_ready_o : out std_logic;
        debug_data_o : out std_logic_vector(31 downto 0);
        debug_valid_o : out std_logic;
        awaddr_o : out std_logic_vector(31 downto 0);
        awprot_o : out std_logic_vector(2 downto 0);
        awvalid_o : out std_logic;
        awready_i : in std_logic;
        wdata_o : out std_logic_vector(31 downto 0);
        wstrb_o : out std_logic_vector(3 downto 0);
        wvalid_o : out std_logic;
        wready_i : in std_logic;
        bresp_i : in std_logic_vector(1 downto 0);
        bvalid_i : in std_logic;
        bready_o : out std_logic;
        araddr_o : out std_logic_vector(31 downto 0);
        arprot_o : out std_logic_vector(2 downto 0);
        arvalid_o : out std_logic;
        arready_i : in std_logic;
        rdata_i : in std_logic_vector(31 downto 0);
        rresp_i : in std_logic_vector(1 downto 0);
        rvalid_i : in std_logic;
        rready_o : out std_logic
    );
end entity;
architecture rtl of elans_core is
    type state_type is (fetch_request, fetch_wait, decode, read_a_request,
        read_a_wait, read_b_request, read_b_wait, serial_clear, serial_run,
        serial_finish, immediate_seed, result_seed, dispatch, shift_discard,
        shift_run, memory_prepare, memory_request,
        memory_wait, store_align, load_align, load_run, pc_transfer,
        write_request, write_wait, commit, halted);
    type pass_type is (increment_pc, execute_value, effective_address, branch_compare, control_target);
    signal state_q : state_type;
    signal pass_q : pass_type;
    signal pc_q : std_logic_vector(31 downto 0);
    signal previous_pc_q : std_logic_vector(31 downto 0);
    signal next_pc_q : std_logic_vector(31 downto 0);
    signal instruction_q : std_logic_vector(31 downto 0);
    signal a_q : std_logic_vector(31 downto 0);
    signal b_q : std_logic_vector(31 downto 0);
    signal result_q : std_logic_vector(31 downto 0);
    signal bit_q : unsigned(4 downto 0);
    signal shift_q : unsigned(4 downto 0);
    signal fault_q : std_logic;
    signal debug_wait_q : std_logic;
    signal debug_ready : std_logic;
    signal opcode : std_logic_vector(6 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);
    signal legal : std_logic;
    signal is_register : std_logic;
    signal is_immediate : std_logic;
    signal is_load : std_logic;
    signal is_store : std_logic;
    signal is_branch : std_logic;
    signal is_jump : std_logic;
    signal is_shift : std_logic;
    signal is_compare : std_logic;
    signal immediate_bit : std_logic;
    signal alu_a_bit : std_logic;
    signal alu_b_bit : std_logic;
    signal alu_use_pc : std_logic;
    signal alu_use_register_b : std_logic;
    signal sign_a_q : std_logic;
    signal sign_b_q : std_logic;
    signal load_fill_q : std_logic;
    signal load_bit : std_logic;
    signal alu_operation : std_logic_vector(2 downto 0);
    signal alu_subtract : std_logic;
    signal alu_clear : std_logic;
    signal alu_step : std_logic;
    signal alu_result : std_logic;
    signal alu_less : std_logic;
    signal alu_equal : std_logic;
    signal signed_less : std_logic;
    signal comparison : std_logic;
    signal branch_taken : std_logic;
    signal target : std_logic_vector(31 downto 0);
    signal misaligned : std_logic;
    signal rf_request : std_logic;
    signal rf_write : std_logic;
    signal rf_index : std_logic_vector(4 downto 0);
    signal rf_input : std_logic;
    signal rf_output : std_logic;
    signal rf_bit_valid : std_logic;
    signal rf_bit_ready : std_logic;
    signal rf_write_valid : std_logic;
    signal rf_cancel : std_logic;
    signal rf_ready : std_logic;
    signal rf_done : std_logic;
    signal bus_request : std_logic;
    signal bus_write : std_logic;
    signal bus_address : std_logic_vector(31 downto 0);
    signal bus_input : std_logic_vector(31 downto 0);
    signal bus_output : std_logic_vector(31 downto 0);
    signal bus_strobe : std_logic_vector(3 downto 0);
    signal bus_ready : std_logic;
    signal bus_done : std_logic;
    signal bus_error : std_logic;
    signal datapath_active : std_logic;
    signal a_shift : std_logic;
    signal a_in : std_logic;
    signal a_load_pc : std_logic;
    signal a_load_bus : std_logic;
    signal b_shift : std_logic;
    signal b_in : std_logic;
    signal result_shift : std_logic;
    signal result_in : std_logic;
    signal result_clear_lsb : std_logic;
    signal next_pc_shift : std_logic;
    signal next_pc_in : std_logic;
    signal next_pc_load : std_logic;
    signal shift_padding : std_logic;
begin
    opcode <= instruction_q(6 downto 0);
    funct3 <= instruction_q(14 downto 12);
    funct7 <= instruction_q(31 downto 25);
    is_register <= '1' when opcode = "0110011" else '0';
    is_immediate <= '1' when opcode = "0010011" else '0';
    is_load <= '1' when opcode = "0000011" else '0';
    is_store <= '1' when opcode = "0100011" else '0';
    is_branch <= '1' when opcode = "1100011" else '0';
    is_jump <= '1' when opcode = "1101111" or opcode = "1100111" else '0';
    is_shift <= '1' when (is_register = '1' or is_immediate = '1') and
                               (funct3 = "001" or funct3 = "101") else '0';
    is_compare <= '1' when (is_register = '1' or is_immediate = '1') and
                                 (funct3 = "010" or funct3 = "011") else '0';
    legal <= '1' when
        (is_register = '1' and (funct7 = "0000000" or
            (funct7 = "0100000" and (funct3 = "000" or funct3 = "101")))) or
        (is_immediate = '1' and ((funct3 /= "001" and funct3 /= "101") or
            (funct3 = "001" and funct7 = "0000000") or
            (funct3 = "101" and (funct7 = "0000000" or funct7 = "0100000")))) or
        (is_load = '1' and (funct3 = "000" or funct3 = "001" or funct3 = "010" or funct3 = "100" or funct3 = "101")) or
        (is_store = '1' and (funct3 = "000" or funct3 = "001" or funct3 = "010")) or
        (is_branch = '1' and (funct3 = "000" or funct3 = "001" or funct3 = "100" or funct3 = "101" or funct3 = "110" or funct3 = "111")) or
        opcode = "0110111" or opcode = "0010111" or opcode = "1101111" or
        (opcode = "1100111" and funct3 = "000") or
        (opcode = "0001111" and funct3 = "000" and instruction_q(31 downto 28) = "0000")
        else '0';
    -- Generate only the immediate bit being transferred. No parallel
    -- immediate bus is connected to the result register's load mux.
    immediate_pr: process (instruction_q, opcode, is_branch, is_store, bit_q) is
        variable n : integer range 0 to 31;
    begin
        n := to_integer(bit_q);
        immediate_bit <= instruction_q(31);
        if opcode = "0110111" or opcode = "0010111" then
            if n < 12 then
                immediate_bit <= '0';
            else
                immediate_bit <= instruction_q(n);
            end if;
        elsif opcode = "1101111" then
            if n = 0 then
                immediate_bit <= '0';
            elsif n < 11 then
                immediate_bit <= instruction_q(n + 20);
            elsif n = 11 then
                immediate_bit <= instruction_q(20);
            elsif n < 20 then
                immediate_bit <= instruction_q(n);
            end if;
        elsif is_branch = '1' then
            if n = 0 then
                immediate_bit <= '0';
            elsif n < 5 then
                immediate_bit <= instruction_q(n + 7);
            elsif n < 11 then
                immediate_bit <= instruction_q(n + 20);
            elsif n = 11 then
                immediate_bit <= instruction_q(7);
            end if;
        elsif is_store = '1' then
            if n < 5 then
                immediate_bit <= instruction_q(n + 7);
            elsif n < 12 then
                immediate_bit <= instruction_q(n + 20);
            end if;
        elsif n < 12 then
            immediate_bit <= instruction_q(n + 20);
        end if;
    end process;
    -- Seed the result shifter with the immediate, then replace each
    -- consumed bit with its corresponding ALU result over a second pass.
    alu_use_pc <= '1' when (pass_q = control_target and opcode /= "1100111") or
        (pass_q = execute_value and opcode = "0010111") else '0';
    alu_use_register_b <= '1' when pass_q = branch_compare or
        (pass_q = execute_value and is_register = '1') else '0';
    alu_a_bit <= next_pc_q(0) when pass_q = increment_pc else a_q(0);
    alu_b_bit <= '1' when pass_q = increment_pc and bit_q = 2 else
                 '0' when pass_q = increment_pc else
                 b_q(0) when alu_use_register_b = '1' else result_q(0);
    alu_operation <= funct3 when pass_q = execute_value and is_compare = '0' and
        (is_register = '1' or is_immediate = '1') else "000";
    alu_subtract <= '1' when pass_q = branch_compare or
        (pass_q = execute_value and (is_compare = '1' or
         (is_register = '1' and funct3 = "000" and funct7 = "0100000"))) else '0';
    alu_clear <= '1' when state_q = serial_clear else '0';
    alu_step <= '1' when state_q = serial_run and fault_i = '0' else '0';
    signed_less <= sign_a_q when sign_a_q /= sign_b_q else alu_less;
    comparison <= signed_less when funct3 = "010" else alu_less;
    branch_taken <= alu_equal when funct3 = "000" else
                    not alu_equal when funct3 = "001" else
                    signed_less when funct3 = "100" else
                    not signed_less when funct3 = "101" else
                    alu_less when funct3 = "110" else not alu_less;
    target <= result_q(31 downto 1) & '0' when opcode = "1100111" else result_q;
    misaligned <= '1' when (funct3(1 downto 0) = "01" and result_q(0) = '1') or
                          (funct3(1 downto 0) = "10" and result_q(1 downto 0) /= "00") else '0';
    fault_o <= fault_q or fault_i;
    pc_o <= pc_q;
    previous_pc_o <= previous_pc_q;
    debug_ready <= '1' when state_q = halted and bus_ready = '1' and
        rf_ready = '1' and debug_wait_q = '0' else '0';
    debug_ready_o <= debug_ready;
    debug_data_o <= a_q;
    debug_valid_o <= rf_done and debug_wait_q;
    rf_request <= '1' when (fault_i = '0' and (state_q = read_a_request or
        state_q = read_b_request or state_q = write_request)) or
        (debug_ready = '1' and debug_request_i = '1') else '0';
    rf_write <= '1' when state_q = write_request else '0';
    rf_index <= debug_index_i when state_q = halted else
        instruction_q(19 downto 15) when state_q = read_a_request else
        instruction_q(24 downto 20) when state_q = read_b_request else instruction_q(11 downto 7);
    rf_input <= next_pc_q(0) when is_jump = '1' else result_q(0);
    rf_write_valid <= '1' when state_q = write_wait and fault_i = '0' else '0';
    rf_cancel <= '1' when fault_i = '1' and state_q /= halted else '0';
    bus_request <= '1' when fault_i = '0' and ((state_q = fetch_request and pc_q(1 downto 0) = "00") or state_q = memory_request) else '0';
    bus_write <= is_store when state_q = memory_request else '0';
    bus_address <= pc_q when state_q = fetch_request else result_q(31 downto 2) & "00";
    bus_strobe <= "1111" when funct3 = "010" else
        "0011" when funct3 = "001" and result_q(1) = '0' else
        "1100" when funct3 = "001" else
        "0001" when result_q(1 downto 0) = "00" else
        "0010" when result_q(1 downto 0) = "01" else
        "0100" when result_q(1 downto 0) = "10" else "1000";
    -- Inactive store lanes are ignored by WSTRB. Rotate right by
    -- (-8 * byte_offset) mod 32 single-bit steps before issuing AXI.
    bus_input <= b_q;
    load_bit <= a_q(0) when funct3 = "010" or bit_q < 8 or
        ((funct3 = "001" or funct3 = "101") and bit_q < 16) else load_fill_q;
    alu_inst: entity work.elans_alu
        generic map (use_async_reset => use_async_reset, use_sync_reset => use_sync_reset,
            async_reset_active => async_reset_active, sync_reset_active => sync_reset_active)
        port map (clock_i => clock_i, async_reset_i => async_reset_i, sync_reset_i => sync_reset_i,
            clear_i => alu_clear, step_i => alu_step, subtract_i => alu_subtract,
            operation_i => alu_operation, a_i => alu_a_bit,
            b_i => alu_b_bit, result_o => alu_result,
            less_unsigned_o => alu_less, equal_o => alu_equal);
    rf_inst: entity work.elans_register_file
        generic map (use_async_reset => use_async_reset, use_sync_reset => use_sync_reset,
            async_reset_active => async_reset_active, sync_reset_active => sync_reset_active, organization => rf_organization)
        port map (clock_i => clock_i, async_reset_i => async_reset_i, sync_reset_i => sync_reset_i,
            cancel_i => rf_cancel, request_i => rf_request, write_i => rf_write,
            index_i => rf_index, data_i => rf_input, bit_valid_i => rf_write_valid,
            bit_ready_o => rf_bit_ready, bit_ready_i => '1', bit_valid_o => rf_bit_valid,
            ready_o => rf_ready, done_o => rf_done, data_o => rf_output);
    axi_inst: entity work.elans_axi_master
        generic map (use_async_reset => use_async_reset, use_sync_reset => use_sync_reset,
            async_reset_active => async_reset_active, sync_reset_active => sync_reset_active)
        port map (clock_i => clock_i, async_reset_i => async_reset_i, sync_reset_i => sync_reset_i,
            request_i => bus_request, write_i => bus_write, address_i => bus_address,
            data_i => bus_input, strobe_i => bus_strobe, ready_o => bus_ready,
            done_o => bus_done, error_o => bus_error, data_o => bus_output,
            awaddr_o => awaddr_o,
            awprot_o => awprot_o,
            awvalid_o => awvalid_o,
            awready_i => awready_i,
            wdata_o => wdata_o,
            wstrb_o => wstrb_o,
            wvalid_o => wvalid_o,
            wready_i => wready_i,
            bresp_i => bresp_i,
            bvalid_i => bvalid_i,
            bready_o => bready_o,
            araddr_o => araddr_o,
            arprot_o => arprot_o,
            arvalid_o => arvalid_o,
            arready_i => arready_i,
            rdata_i => rdata_i,
            rresp_i => rresp_i,
            rvalid_i => rvalid_i,
            rready_o => rready_o);
    -- One shift enable and one serial input per temporary. All serial
    -- operations share the same fixed right-shift wiring, including SLL.
    datapath_active <= '0' when fault_i = '1' and state_q /= halted else '1';
    shift_padding <= '1' when funct3 = "001" and shift_q /= 0 else '0';
    a_load_pc <= '1' when state_q = serial_clear and
        pass_q /= increment_pc and alu_use_pc = '1' else '0';
    a_load_bus <= '1' when state_q = memory_wait and bus_done = '1' and
        bus_error = '0' and is_load = '1' else '0';
    a_shift <= '1' when
        (state_q = read_a_wait and rf_bit_valid = '1') or
        (state_q = halted and debug_wait_q = '1' and rf_bit_valid = '1') or
        (state_q = serial_run and pass_q /= increment_pc) or
        (state_q = load_align and shift_q /= 0) or state_q = load_run or
        (state_q = shift_discard and funct3 /= "001" and shift_q /= 0) or
        (state_q = shift_run and shift_padding = '0') else '0';
    a_in <= rf_output when state_q = read_a_wait or state_q = halted else
            a_q(0) when state_q = serial_run else
            load_fill_q when state_q = shift_discard or state_q = shift_run else '0';
    b_shift <= '1' when
        (state_q = read_b_wait and rf_bit_valid = '1') or
        (state_q = serial_run and pass_q /= increment_pc and alu_use_register_b = '1') or
        (state_q = store_align and shift_q /= 0) else '0';
    b_in <= rf_output when state_q = read_b_wait else b_q(0);
    result_shift <= '1' when
        (state_q = serial_run and pass_q /= increment_pc) or
        state_q = immediate_seed or state_q = result_seed or
        state_q = shift_run or state_q = load_run or state_q = pc_transfer or
        (state_q = write_wait and rf_bit_ready = '1' and is_jump = '0') else '0';
    result_in <= alu_result when state_q = serial_run else
                 immediate_bit when state_q = immediate_seed or
                     (state_q = result_seed and opcode = "0110111") else
                 load_fill_q when state_q = result_seed and bit_q = 0 else
                 '0' when state_q = result_seed else
                 '0' when state_q = shift_run and shift_padding = '1' else
                 a_q(0) when state_q = shift_run else
                 load_bit when state_q = load_run else result_q(0);
    result_clear_lsb <= '1' when state_q = serial_finish and
        pass_q = control_target and opcode = "1100111" and
        target(1 downto 0) = "00" else '0';
    next_pc_load <= '1' when state_q = serial_clear and pass_q = increment_pc else '0';
    next_pc_shift <= '1' when
        (state_q = serial_run and pass_q = increment_pc) or state_q = pc_transfer or
        (state_q = write_wait and rf_bit_ready = '1' and is_jump = '1') else '0';
    next_pc_in <= alu_result when state_q = serial_run else
                  result_q(0) when state_q = pc_transfer else next_pc_q(0);

    datapath_pr: process (clock_i, async_reset_i) is
    begin
        if (async_reset_i = async_reset_active) and use_async_reset then
            a_q <= (others => '0');
            b_q <= (others => '0');
            result_q <= (others => '0');
            next_pc_q <= reset_pc;
        elsif rising_edge(clock_i) then
            if (sync_reset_i = sync_reset_active) and use_sync_reset then
                a_q <= (others => '0');
                b_q <= (others => '0');
                result_q <= (others => '0');
                next_pc_q <= reset_pc;
            elsif datapath_active = '1' then
                if a_load_pc = '1' then
                    a_q <= pc_q;
                elsif a_load_bus = '1' then
                    a_q <= bus_output;
                elsif a_shift = '1' then
                    a_q <= a_in & a_q(31 downto 1);
                end if;
                if b_shift = '1' then
                    b_q <= b_in & b_q(31 downto 1);
                end if;
                if result_shift = '1' then
                    result_q <= result_in & result_q(31 downto 1);
                elsif result_clear_lsb = '1' then
                    result_q(0) <= '0';
                end if;
                if next_pc_load = '1' then
                    next_pc_q <= pc_q;
                elsif next_pc_shift = '1' then
                    next_pc_q <= next_pc_in & next_pc_q(31 downto 1);
                end if;
            end if;
        end if;
    end process;

    controller_pr: process (clock_i, async_reset_i) is
    begin
        if (async_reset_i = async_reset_active) and use_async_reset then
                state_q <= fetch_request;
                pass_q <= increment_pc;
                pc_q <= reset_pc;
                previous_pc_q <= reset_pc;
                instruction_q <= (others => '0');
                bit_q <= (others => '0');
                shift_q <= (others => '0');
                fault_q <= '0';
                debug_wait_q <= '0';
                sign_a_q <= '0';
                sign_b_q <= '0';
                load_fill_q <= '0';
        elsif rising_edge(clock_i) then
            if (sync_reset_i = sync_reset_active) and use_sync_reset then
                state_q <= fetch_request;
                pass_q <= increment_pc;
                pc_q <= reset_pc;
                previous_pc_q <= reset_pc;
                instruction_q <= (others => '0');
                bit_q <= (others => '0');
                shift_q <= (others => '0');
                fault_q <= '0';
                debug_wait_q <= '0';
                sign_a_q <= '0';
                sign_b_q <= '0';
                load_fill_q <= '0';
            else
                if fault_i = '1' and state_q /= halted then
                    fault_q <= '1';
                    state_q <= halted;
                else
                    if state_q = fetch_request then
                        if pc_q(1 downto 0) /= "00" then
                            fault_q <= '1';
                            state_q <= halted;
                        elsif bus_ready = '1' then
                            state_q <= fetch_wait;
                        end if;
                    elsif state_q = fetch_wait then
                        if bus_done = '1' then
                            if bus_error = '1' then
                                fault_q <= '1';
                                state_q <= halted;
                            else
                                instruction_q <= bus_output;
                                state_q <= decode;
                            end if;
                        end if;
                    elsif state_q = decode then
                        if legal = '0' then
                            fault_q <= '1';
                            state_q <= halted;
                        else
                            state_q <= read_a_request;
                        end if;
                    elsif state_q = read_a_request then
                        if rf_ready = '1' then
                            state_q <= read_a_wait;
                        end if;
                    elsif state_q = read_a_wait then
                        if rf_done = '1' then
                            state_q <= read_b_request;
                        end if;
                    elsif state_q = read_b_request then
                        if rf_ready = '1' then
                            state_q <= read_b_wait;
                        end if;
                    elsif state_q = read_b_wait then
                        if rf_done = '1' then
                            pass_q <= increment_pc;
                            state_q <= serial_clear;
                        end if;
                    elsif state_q = serial_clear then
                        bit_q <= (others => '0');
                        if pass_q /= increment_pc then
                            if alu_use_pc = '1' then
                                sign_a_q <= pc_q(31);
                            else
                                sign_a_q <= a_q(31);
                            end if;
                            if alu_use_register_b = '1' then
                                sign_b_q <= b_q(31);
                            else
                                sign_b_q <= instruction_q(31);
                            end if;
                        end if;
                        if pass_q /= increment_pc and alu_use_register_b = '0' then
                            state_q <= immediate_seed;
                        else
                            state_q <= serial_run;
                        end if;
                    elsif state_q = immediate_seed then
                        if bit_q = 31 then
                            bit_q <= (others => '0');
                            state_q <= serial_run;
                        else
                            bit_q <= bit_q + 1;
                        end if;
                    elsif state_q = result_seed then
                        if bit_q = 31 then
                            state_q <= write_request;
                        else
                            bit_q <= bit_q + 1;
                        end if;
                    elsif state_q = serial_run then
                        if bit_q = 31 then
                            state_q <= serial_finish;
                        else
                            bit_q <= bit_q + 1;
                        end if;
                    elsif state_q = serial_finish then
                        if pass_q = increment_pc then
                            state_q <= dispatch;
                        elsif pass_q = branch_compare then
                            if branch_taken = '1' then
                                pass_q <= control_target;
                                state_q <= serial_clear;
                            else
                                state_q <= commit;
                            end if;
                        elsif pass_q = control_target then
                            if target(1 downto 0) /= "00" then
                                fault_q <= '1';
                                state_q <= halted;
                            elsif is_jump = '1' then
                                -- Only JALR changes bit zero; all other bits
                                -- already contain the destination.
                                state_q <= write_request;
                            else
                                bit_q <= (others => '0');
                                state_q <= pc_transfer;
                            end if;
                        elsif pass_q = effective_address then
                            state_q <= memory_prepare;
                        else
                            if is_compare = '1' then
                                load_fill_q <= comparison;
                                bit_q <= (others => '0');
                                state_q <= result_seed;
                            else
                                state_q <= write_request;
                            end if;
                        end if;
                    elsif state_q = dispatch then
                        if opcode = "0110111" then
                            bit_q <= (others => '0');
                            state_q <= result_seed;
                        elsif opcode = "0001111" then
                            state_q <= commit;
                        elsif is_shift = '1' then
                            bit_q <= (others => '0');
                            if funct3 = "101" and instruction_q(30) = '1' then
                                load_fill_q <= a_q(31);
                            else
                                load_fill_q <= '0';
                            end if;
                            if is_immediate = '1' then
                                shift_q <= unsigned(instruction_q(24 downto 20));
                            else
                                shift_q <= unsigned(b_q(4 downto 0));
                            end if;
                            state_q <= shift_discard;
                        else
                            if is_branch = '1' then
                                pass_q <= branch_compare;
                            elsif is_jump = '1' then
                                pass_q <= control_target;
                            elsif is_load = '1' or is_store = '1' then
                                pass_q <= effective_address;
                            else
                                pass_q <= execute_value;
                            end if;
                            state_q <= serial_clear;
                        end if;
                    elsif state_q = shift_discard then
                        -- Right shifts discard low bits first. Left shifts
                        -- emit leading zero bits instead, without shifting A.
                        if funct3 = "001" or shift_q = 0 then
                            state_q <= shift_run;
                        else
                            shift_q <= shift_q - 1;
                        end if;
                    elsif state_q = shift_run then
                        if shift_padding = '1' then
                            shift_q <= shift_q - 1;
                        end if;
                        if bit_q = 31 then
                            state_q <= write_request;
                        else
                            bit_q <= bit_q + 1;
                        end if;
                    elsif state_q = memory_prepare then
                        if misaligned = '1' then
                            fault_q <= '1';
                            state_q <= halted;
                        else
                            if is_store = '1' then
                                shift_q <= to_unsigned(0, 5) - unsigned(result_q(1 downto 0) & "000");
                                state_q <= store_align;
                            else
                                state_q <= memory_request;
                            end if;
                        end if;
                    elsif state_q = store_align then
                        if shift_q = 0 then
                            state_q <= memory_request;
                        else
                            shift_q <= shift_q - 1;
                        end if;
                    elsif state_q = memory_request then
                        if bus_ready = '1' then
                            state_q <= memory_wait;
                        end if;
                    elsif state_q = memory_wait then
                        if bus_done = '1' then
                            if bus_error = '1' then
                                fault_q <= '1';
                                state_q <= halted;
                            elsif is_load = '1' then
                                shift_q <= unsigned(result_q(1 downto 0) & "000");
                                state_q <= load_align;
                            else
                                state_q <= commit;
                            end if;
                        end if;
                    elsif state_q = load_align then
                        if shift_q = 0 then
                            bit_q <= (others => '0');
                            load_fill_q <= '0';
                            state_q <= load_run;
                        else
                            shift_q <= shift_q - 1;
                        end if;
                    elsif state_q = load_run then
                        if (funct3 = "000" and bit_q = 7) or
                           (funct3 = "001" and bit_q = 15) then
                            load_fill_q <= a_q(0);
                        end if;
                        if bit_q = 31 then
                            state_q <= write_request;
                        else
                            bit_q <= bit_q + 1;
                        end if;
                    elsif state_q = write_request then
                        if rf_ready = '1' then
                            state_q <= write_wait;
                        end if;
                    elsif state_q = write_wait then
                        if rf_done = '1' then
                            if is_jump = '1' then
                                bit_q <= (others => '0');
                                state_q <= pc_transfer;
                            else
                                state_q <= commit;
                            end if;
                        end if;
                    elsif state_q = pc_transfer then
                        -- The link has already been written. Reuse the next-PC
                        -- shifter for the branch/jump destination, then commit
                        -- PC and its debug snapshot atomically.
                        if bit_q = 31 then
                            state_q <= commit;
                        else
                            bit_q <= bit_q + 1;
                        end if;
                    elsif state_q = commit then
                        previous_pc_q <= pc_q;
                        pc_q <= next_pc_q;
                        state_q <= fetch_request;
                    elsif state_q = halted then
                        if debug_ready = '1' and debug_request_i = '1' then
                            debug_wait_q <= '1';
                        elsif rf_done = '1' and debug_wait_q = '1' then
                            debug_wait_q <= '0';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
