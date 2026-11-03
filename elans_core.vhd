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
    subtype extension_11_type is std_logic_vector(10 downto 0);
    subtype extension_16_type is std_logic_vector(15 downto 0);
    subtype extension_19_type is std_logic_vector(18 downto 0);
    subtype extension_20_type is std_logic_vector(19 downto 0);
    subtype extension_24_type is std_logic_vector(23 downto 0);
    subtype extension_31_type is std_logic_vector(30 downto 0);

    type state_type is (fetch_request, fetch_wait, decode, read_a_request,
        read_a_wait, read_b_request, read_b_wait, serial_clear, serial_run,
        serial_finish, dispatch, shift_run, memory_prepare, memory_request,
        memory_wait, write_request, write_wait, commit, halted);
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
    signal immediate : std_logic_vector(31 downto 0);
    signal alu_a_word : std_logic_vector(31 downto 0);
    signal alu_b_word : std_logic_vector(31 downto 0);
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
    signal rf_input : std_logic_vector(31 downto 0);
    signal rf_output : std_logic_vector(31 downto 0);
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
    signal byte_lane : std_logic_vector(7 downto 0);
    signal half_lane : std_logic_vector(15 downto 0);
    signal load_value : std_logic_vector(31 downto 0);
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
    -- Immediate wiring only: no immediate storage or arithmetic.
    immediate <= instruction_q(31 downto 12) & x"000" when opcode = "0110111" or opcode = "0010111" else
        extension_11_type'(others => instruction_q(31)) & instruction_q(31) & instruction_q(19 downto 12) & instruction_q(20) & instruction_q(30 downto 21) & '0' when opcode = "1101111" else
        extension_19_type'(others => instruction_q(31)) & instruction_q(31) & instruction_q(7) & instruction_q(30 downto 25) & instruction_q(11 downto 8) & '0' when is_branch = '1' else
        extension_20_type'(others => instruction_q(31)) & instruction_q(31 downto 25) & instruction_q(11 downto 7) when is_store = '1' else
        extension_20_type'(others => instruction_q(31)) & instruction_q(31 downto 20);
    alu_a_word <= pc_q when pass_q = increment_pc or
        (pass_q = control_target and opcode /= "1100111") or
        (pass_q = execute_value and opcode = "0010111") else a_q;
    alu_b_word <= x"00000004" when pass_q = increment_pc else
                  b_q when pass_q = branch_compare or (pass_q = execute_value and is_register = '1') else immediate;
    alu_operation <= funct3 when pass_q = execute_value and is_compare = '0' and
        (is_register = '1' or is_immediate = '1') else "000";
    alu_subtract <= '1' when pass_q = branch_compare or
        (pass_q = execute_value and (is_compare = '1' or
         (is_register = '1' and funct3 = "000" and funct7 = "0100000"))) else '0';
    alu_clear <= '1' when state_q = serial_clear else '0';
    alu_step <= '1' when state_q = serial_run and fault_i = '0' else '0';
    signed_less <= alu_a_word(31) when alu_a_word(31) /= alu_b_word(31) else alu_less;
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
    debug_data_o <= rf_output;
    debug_valid_o <= rf_done and debug_wait_q;
    rf_request <= '1' when (fault_i = '0' and (state_q = read_a_request or
        state_q = read_b_request or state_q = write_request)) or
        (debug_ready = '1' and debug_request_i = '1') else '0';
    rf_write <= '1' when state_q = write_request else '0';
    rf_index <= debug_index_i when state_q = halted else
        instruction_q(19 downto 15) when state_q = read_a_request else
        instruction_q(24 downto 20) when state_q = read_b_request else instruction_q(11 downto 7);
    rf_input <= next_pc_q when is_jump = '1' else result_q;
    bus_request <= '1' when fault_i = '0' and ((state_q = fetch_request and pc_q(1 downto 0) = "00") or state_q = memory_request) else '0';
    bus_write <= is_store when state_q = memory_request else '0';
    bus_address <= pc_q when state_q = fetch_request else result_q(31 downto 2) & "00";
    bus_strobe <= "1111" when funct3 = "010" else
        "0011" when funct3 = "001" and result_q(1) = '0' else
        "1100" when funct3 = "001" else
        "0001" when result_q(1 downto 0) = "00" else
        "0010" when result_q(1 downto 0) = "01" else
        "0100" when result_q(1 downto 0) = "10" else "1000";
    bus_input <= b_q when funct3 = "010" else
        x"0000" & b_q(15 downto 0) when funct3 = "001" and result_q(1) = '0' else
        b_q(15 downto 0) & x"0000" when funct3 = "001" else
        x"000000" & b_q(7 downto 0) when result_q(1 downto 0) = "00" else
        x"0000" & b_q(7 downto 0) & x"00" when result_q(1 downto 0) = "01" else
        x"00" & b_q(7 downto 0) & x"0000" when result_q(1 downto 0) = "10" else
        b_q(7 downto 0) & x"000000";
    byte_lane <= bus_output(7 downto 0) when result_q(1 downto 0) = "00" else
        bus_output(15 downto 8) when result_q(1 downto 0) = "01" else
        bus_output(23 downto 16) when result_q(1 downto 0) = "10" else bus_output(31 downto 24);
    half_lane <= bus_output(15 downto 0) when result_q(1) = '0' else bus_output(31 downto 16);
    load_value <= extension_24_type'(others => byte_lane(7)) & byte_lane when funct3 = "000" else
        extension_16_type'(others => half_lane(15)) & half_lane when funct3 = "001" else
        x"000000" & byte_lane when funct3 = "100" else
        x"0000" & half_lane when funct3 = "101" else bus_output;
    alu_inst: entity work.elans_alu
        generic map (use_async_reset => use_async_reset, use_sync_reset => use_sync_reset,
            async_reset_active => async_reset_active, sync_reset_active => sync_reset_active)
        port map (clock_i => clock_i, async_reset_i => async_reset_i, sync_reset_i => sync_reset_i,
            clear_i => alu_clear, step_i => alu_step, subtract_i => alu_subtract,
            operation_i => alu_operation, a_i => alu_a_word(to_integer(bit_q)),
            b_i => alu_b_word(to_integer(bit_q)), result_o => alu_result,
            less_unsigned_o => alu_less, equal_o => alu_equal);
    rf_inst: entity work.elans_register_file
        generic map (use_async_reset => use_async_reset, use_sync_reset => use_sync_reset,
            async_reset_active => async_reset_active, sync_reset_active => sync_reset_active, organization => rf_organization)
        port map (clock_i => clock_i, async_reset_i => async_reset_i, sync_reset_i => sync_reset_i,
            request_i => rf_request, write_i => rf_write, index_i => rf_index, data_i => rf_input,
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
    controller_pr: process (clock_i, async_reset_i) is
    begin
        if (async_reset_i = async_reset_active) and use_async_reset then
                state_q <= fetch_request;
                pass_q <= increment_pc;
                pc_q <= reset_pc;
                previous_pc_q <= reset_pc;
                next_pc_q <= reset_pc;
                instruction_q <= (others => '0');
                a_q <= (others => '0');
                b_q <= (others => '0');
                result_q <= (others => '0');
                bit_q <= (others => '0');
                shift_q <= (others => '0');
                fault_q <= '0';
                debug_wait_q <= '0';
        elsif rising_edge(clock_i) then
            if (sync_reset_i = sync_reset_active) and use_sync_reset then
                state_q <= fetch_request;
                pass_q <= increment_pc;
                pc_q <= reset_pc;
                previous_pc_q <= reset_pc;
                next_pc_q <= reset_pc;
                instruction_q <= (others => '0');
                a_q <= (others => '0');
                b_q <= (others => '0');
                result_q <= (others => '0');
                bit_q <= (others => '0');
                shift_q <= (others => '0');
                fault_q <= '0';
                debug_wait_q <= '0';
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
                            a_q <= rf_output;
                            state_q <= read_b_request;
                        end if;
                    elsif state_q = read_b_request then
                        if rf_ready = '1' then
                            state_q <= read_b_wait;
                        end if;
                    elsif state_q = read_b_wait then
                        if rf_done = '1' then
                            b_q <= rf_output;
                            pass_q <= increment_pc;
                            state_q <= serial_clear;
                        end if;
                    elsif state_q = serial_clear then
                        bit_q <= (others => '0');
                        state_q <= serial_run;
                    elsif state_q = serial_run then
                        result_q(to_integer(bit_q)) <= alu_result;
                        if bit_q = 31 then
                            state_q <= serial_finish;
                        else
                            bit_q <= bit_q + 1;
                        end if;
                    elsif state_q = serial_finish then
                        if pass_q = increment_pc then
                            next_pc_q <= result_q;
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
                                result_q <= target;
                                state_q <= write_request;
                            else
                                next_pc_q <= target;
                                state_q <= commit;
                            end if;
                        elsif pass_q = effective_address then
                            state_q <= memory_prepare;
                        else
                            if is_compare = '1' then
                                result_q <= extension_31_type'(others => '0') & comparison;
                            end if;
                            state_q <= write_request;
                        end if;
                    elsif state_q = dispatch then
                        if opcode = "0110111" then
                            result_q <= immediate;
                            state_q <= write_request;
                        elsif opcode = "0001111" then
                            state_q <= commit;
                        elsif is_shift = '1' then
                            result_q <= a_q;
                            if is_immediate = '1' then
                                shift_q <= unsigned(instruction_q(24 downto 20));
                            else
                                shift_q <= unsigned(b_q(4 downto 0));
                            end if;
                            state_q <= shift_run;
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
                    elsif state_q = shift_run then
                        if shift_q = 0 then
                            state_q <= write_request;
                        else
                            shift_q <= shift_q - 1;
                            if funct3 = "001" then
                                result_q <= result_q(30 downto 0) & '0';
                            elsif instruction_q(30) = '1' then
                                result_q <= result_q(31) & result_q(31 downto 1);
                            else
                                result_q <= '0' & result_q(31 downto 1);
                            end if;
                        end if;
                    elsif state_q = memory_prepare then
                        if misaligned = '1' then
                            fault_q <= '1';
                            state_q <= halted;
                        else
                            state_q <= memory_request;
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
                                result_q <= load_value;
                                state_q <= write_request;
                            else
                                state_q <= commit;
                            end if;
                        end if;
                    elsif state_q = write_request then
                        if rf_ready = '1' then
                            state_q <= write_wait;
                        end if;
                    elsif state_q = write_wait then
                        if rf_done = '1' then
                            state_q <= commit;
                        end if;
                    elsif state_q = commit then
                        previous_pc_q <= pc_q;
                        if is_jump = '1' then
                            pc_q <= result_q;
                        else
                            pc_q <= next_pc_q;
                        end if;
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
