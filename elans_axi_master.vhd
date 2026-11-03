library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity elans_axi_master is
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
        request_i : in std_logic;
        write_i : in std_logic;
        address_i : in std_logic_vector(31 downto 0);
        data_i : in std_logic_vector(31 downto 0);
        strobe_i : in std_logic_vector(3 downto 0);
        ready_o : out std_logic;
        done_o : out std_logic;
        error_o : out std_logic;
        data_o : out std_logic_vector(31 downto 0);
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
-- Unbuffered, single-outstanding AXI4-Lite adapter.
-- The requester owns address_i/data_i/strobe_i and must hold them from
-- request acceptance through the completion handshake, including on faults.
-- done_o/error_o/data_o are sampled on that handshake's rising edge;
-- response data and error are not retained after completion.
architecture rtl of elans_axi_master is
    signal busy_q : std_logic;
    signal write_q : std_logic;
    signal aw_q : std_logic;
    signal w_q : std_logic;
    signal ar_q : std_logic;
    signal read_ready : std_logic;
    signal write_ready : std_logic;
    signal read_complete : std_logic;
    signal write_complete : std_logic;
begin
    ready_o <= not busy_q;
    read_ready <= busy_q and not write_q and not ar_q;
    write_ready <= busy_q and write_q and not aw_q and not w_q;
    read_complete <= read_ready and rvalid_i;
    write_complete <= write_ready and bvalid_i;
    done_o <= read_complete or write_complete;
    error_o <= '1' when
        (read_complete = '1' and rresp_i /= "00") or
        (write_complete = '1' and bresp_i /= "00") else '0';
    data_o <= rdata_i;
    awaddr_o <= address_i;
    araddr_o <= address_i;
    awprot_o <= "000";
    arprot_o <= "000";
    wdata_o <= data_i;
    wstrb_o <= strobe_i;
    awvalid_o <= aw_q;
    wvalid_o <= w_q;
    arvalid_o <= ar_q;
    bready_o <= write_ready;
    rready_o <= read_ready;

    axi_pr: process (clock_i, async_reset_i) is
    begin
        if (async_reset_i = async_reset_active) and use_async_reset then
            busy_q <= '0';
            write_q <= '0';
            aw_q <= '0';
            w_q <= '0';
            ar_q <= '0';
        elsif rising_edge(clock_i) then
            if (sync_reset_i = sync_reset_active) and use_sync_reset then
                busy_q <= '0';
                write_q <= '0';
                aw_q <= '0';
                w_q <= '0';
                ar_q <= '0';
            elsif busy_q = '0' then
                if request_i = '1' then
                    busy_q <= '1';
                    write_q <= write_i;
                    aw_q <= write_i;
                    w_q <= write_i;
                    ar_q <= not write_i;
                end if;
            else
                -- AW and W can complete in either order, with arbitrary
                -- independent backpressure. Never combine their flags.
                if aw_q = '1' and awready_i = '1' then
                    aw_q <= '0';
                end if;
                if w_q = '1' and wready_i = '1' then
                    w_q <= '0';
                end if;
                if ar_q = '1' and arready_i = '1' then
                    ar_q <= '0';
                end if;
                if read_complete = '1' or write_complete = '1' then
                    busy_q <= '0';
                end if;
            end if;
        end if;
    end process;
end architecture;
