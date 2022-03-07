-- Enhanced PWM (ePWM) module
-- Date: 2022/03/07
-- Author: Ander Gonzalez
-- This is a simillar PWM module implementation to ePWM modules of TI's C2000 family DSPs

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ePWM is
port(
	-- general
    i_clk       : in std_logic;	-- input clock
	
	-- time_base
	i_clk_sync	: in std_logic;	 -- time base synchronization input
	i_direction	: in std_logic_vector (1 downto 0); -- counter direction
	i_phase		: in unsigned (15 downto 0); -- counter phase (shift)
	i_prd		: in unsigned (15 downto 0); -- PWM period	
	o_ctr_prd	: out std_logic := '0'; -- compare r_ctr = i_prd
	o_ctr_zero	: out std_logic := '0'; -- compare r_ctr = zero
	o_ctr_dir	: out std_logic := '1'; -- current direction of the counting
	
	--register_update
	i_cmpa		: in unsigned (15 downto 0); -- COMP A value (shadow register)
	i_cmpb		: in unsigned (15 downto 0); -- COMP B value (shadow register)
	i_reg_update: in std_logic; -- defines when to update from shadow registers. 0: when r_ctr=0, 1: when r_ctr=i_prd
	
	-- counter_compare
	o_ctr_cmpa	: out std_logic := '0'; -- compare r_ctr = i_cmpa
	o_ctr_cmpb	: out std_logic := '0'; -- compare r_ctr = i_cmpb
	
	-- action_qualifier
	i_AQCTLA	: in std_logic_vector (11 downto 0); -- Action-Qualifier output A control register
	i_AQCTLB	: in std_logic_vector (11 downto 0); -- Action-Qualifier output B control register
	--o_ePWMA_aq	: out std_logic := '0'; -- ePWMA output from action_qualifier block
	--o_ePWMB_aq	: out std_logic := '0';  -- ePWMB output from action_qualifier block
	
	-- dead_band
	i_DBCTL	: in std_logic_vector (6 downto 0):= (others =>'0'); -- Dead-band generator control register
	i_DBRED	: in unsigned (9 downto 0):= (others =>'0'); -- Dead-band generator rising edge delay register
	i_DBFED	: in unsigned (9 downto 0):= (others =>'0') -- Dead-band generator falling edge delay register	
	
	);
end ePWM;
 
architecture rtl of ePWM is

    -- time_base: outputs
	signal r_ctr : unsigned (15 downto 0):=(others =>'0'); -- counter
	signal w_ctr_dir : std_logic :='1'; -- current direction of the counting
	signal w_ctr_prd	: std_logic := '0'; -- compare r_ctr = i_prd
	signal w_ctr_zero	: std_logic := '0'; -- compare r_ctr = zero
	
	-- register_update: outputs 
	signal r_cmpa_act : unsigned (15 downto 0):=(others =>'0'); -- COMP A value (active register)
	signal r_cmpb_act : unsigned (15 downto 0):=(others =>'0'); -- COMP B value (active register)
	
	-- counter_compare: outputs
	signal w_ctr_cmpa	: std_logic := '0'; -- compare r_ctr = i_cmpa
	signal w_ctr_cmpb	: std_logic := '0'; -- compare r_ctr = i_cmpb
	
	-- action_qualifier: outputs
	signal w_ePWMA_aq	: std_logic := '0'; -- ePWMA output from action_qualifier block
	signal w_ePWMB_aq	: std_logic := '0';  -- ePWMB output from action_qualifier block
	-- action_qualifier: vector i_AQCTLA slicing
	alias a_cbd : std_logic_vector (1 downto 0) is i_AQCTLA(11 downto 10);
	alias a_cbu : std_logic_vector (1 downto 0) is i_AQCTLA(9 downto 8);
	alias a_cad : std_logic_vector (1 downto 0) is i_AQCTLA(7 downto 6);
	alias a_cau : std_logic_vector (1 downto 0) is i_AQCTLA(5 downto 4);
	alias a_prd : std_logic_vector (1 downto 0) is i_AQCTLA(3 downto 2);
	alias a_zro : std_logic_vector (1 downto 0) is i_AQCTLA(1 downto 0);
	-- action_qualifier: vector i_AQCTLB slicing
	alias b_cbd : std_logic_vector (1 downto 0) is i_AQCTLB(11 downto 10);
	alias b_cbu : std_logic_vector (1 downto 0) is i_AQCTLB(9 downto 8);
	alias b_cad : std_logic_vector (1 downto 0) is i_AQCTLB(7 downto 6);
	alias b_cau : std_logic_vector (1 downto 0) is i_AQCTLB(5 downto 4);
	alias b_prd : std_logic_vector (1 downto 0) is i_AQCTLB(3 downto 2);
	alias b_zro : std_logic_vector (1 downto 0) is i_AQCTLB(1 downto 0);
	
	-- dead_band: outputs
	signal w_ePWMA_db	: std_logic := '0'; -- ePWMA output from dead_band block
	signal w_ePWMB_db	: std_logic := '0'; -- ePWMB output from dead_band block
	-- dead_band: internal signals
	signal w_RED	: std_logic := '0'; -- Rising edge delay wire
	signal w_FED	: std_logic := '0'; -- Falling edge delay wire
	signal w_RED_ctr_out	: std_logic := '0'; -- Rising edge delay counter output
	signal w_FED_ctr_out	: std_logic := '0'; -- Falling edge delay counter output
	signal w_RED_ctr_in	: std_logic := '0'; -- Rising edge delay counter input
	signal w_FED_ctr_in	: std_logic := '0'; -- Falling edge delay counter input
	signal w_RED_ctr	: unsigned (15 downto 0) := (others =>'0'); -- Rising edge delay counter 
	signal w_FED_ctr	: unsigned (15 downto 0) := (others =>'0'); -- Falling edge delay counter 
	-- dead_band: vector i_DBCTL slicing
	alias db_halfcycle : std_logic is i_DBCTL(6);
	alias db_in_mode : std_logic_vector (1 downto 0) is i_DBCTL(5 downto 4);
	alias db_polsel : std_logic_vector (1 downto 0) is i_DBCTL(3 downto 2);
	alias db_out_mode : std_logic_vector (1 downto 0) is i_DBCTL(1 downto 0);

begin
	time_base : process(i_clk) is
	begin
		if rising_edge(i_clk) then
			-- default values here
			o_ctr_prd <= '0';
			o_ctr_zero <= '0';
			w_ctr_prd <= '0';
			w_ctr_zero <= '0';
			
			if i_clk_sync = '1' then
				r_ctr <= i_phase;
				w_ctr_dir <= '1'; --up count by default
				o_ctr_dir <= '1'; -- copy previous line for output generation
				if i_direction = "01" then
					w_ctr_dir <= '0';
					o_ctr_dir <= '0'; -- copy previous line for output generation
				end if;
				if i_direction = "10" then -- if count updown mode
					if i_phase > i_prd/2 then
						--phase is >180deg, therefore direction is down
						w_ctr_dir<='0';
						o_ctr_dir <= '0'; -- copy previous line for output generation
					end if;
				end if;
						
						
			else
				case i_direction is 
					when "00" => -- count up
						w_ctr_dir <= '1';
						o_ctr_dir <= '1'; -- copy previous line for output generation
						if r_ctr < i_prd then
							r_ctr <= r_ctr +1;
							if r_ctr = i_prd-1 then
								o_ctr_prd <= '1';
								w_ctr_prd <= '1';
							end if;
						else
							r_ctr <= (others =>'0');
							
							o_ctr_zero <= '1';
							w_ctr_zero <= '1';
						end if;
						
					when "01" => -- count down
						w_ctr_dir <= '0';
						o_ctr_dir <= '0'; -- copy previous line for output generation
						if r_ctr > "0000000000000000" then
							r_ctr <= r_ctr -1;
							if r_ctr = "0000000000000001" then
								o_ctr_zero <= '1';
								w_ctr_zero <= '1';
							end if;
						else
							r_ctr <= i_prd;
							o_ctr_prd <= '1';
							w_ctr_prd <= '1';
						end if;
					
					when "10" => -- count updown
						if w_ctr_dir = '1' then
							--counting up
							if r_ctr = i_prd-1 then
								w_ctr_dir <= '0';
								o_ctr_dir <= '0'; -- copy previous line for output generation
								o_ctr_prd <= '1';
								w_ctr_prd <= '1';
							end if;
							r_ctr <= r_ctr +1;					
							
						else
							--counting down
							if r_ctr = "0000000000000001" then
								o_ctr_zero <= '1';
								w_ctr_zero <= '1';
								w_ctr_dir <= '1';
								o_ctr_dir <= '1'; -- copy previous line for output generation
							
							end if;
							r_ctr <= r_ctr -1;	
							
						end if;
					when "11" => -- time base freeze (do nothing)
					when others => -- to avoid compiler error?
				end case;
			end if;
		end if;
	end process time_base;
	
	register_update : process(i_clk) is -- updates active registers from shadow registers
	begin
		if rising_edge(i_clk) then
			if w_ctr_zero = '1' then
				if i_reg_update = '0' then
					-- update
					r_cmpa_act <= i_cmpa;
					r_cmpb_act <= i_cmpb;
				end if;
			end if;
			if w_ctr_prd = '1' then
				if i_reg_update = '1' then
					-- update
					r_cmpa_act <= i_cmpa;
					r_cmpb_act <= i_cmpb;
				end if;
			end if;
		end if;
	end process register_update;
	
    counter_compare : process(i_clk) is
    begin
        if rising_edge(i_clk) then
            -- Default values
            w_ctr_cmpa <= '0'; 
			o_ctr_cmpa <= '0'; -- copy previous line for output generation
			w_ctr_cmpb <= '0'; 
			o_ctr_cmpb <= '0'; -- copy previous line for output generation
			
			if w_ctr_dir = '1' then
			
				if r_ctr = r_cmpa_act-1 then
					w_ctr_cmpa <= '1'; 
					o_ctr_cmpa <= '1'; -- copy previous line for output generation
				end if;
				
				if r_ctr = r_cmpb_act-1 then
					w_ctr_cmpb <= '1'; 
					o_ctr_cmpb <= '1'; -- copy previous line for output generation
				end if;
			else
				if r_ctr = r_cmpa_act+1 then
					w_ctr_cmpa <= '1'; 
					o_ctr_cmpa <= '1'; -- copy previous line for output generation
				end if;
				
				if r_ctr = r_cmpb_act+1 then
					w_ctr_cmpb <= '1'; 
					o_ctr_cmpb <= '1'; -- copy previous line for output generation
				end if;
			end if;
        end if;
    end process counter_compare;
 
	action_qualifier : process(i_clk) is
	begin
		if rising_edge(i_clk) then
			-- Default values
			--o_ePWMA_aq <= '0';
			--o_ePWMB_aq <= '0';
			case i_direction is
				when "00" => -- count up direction
					if w_ctr_zero = '1' then -- Counter equals zero
						case a_zro is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
						case b_zro is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
					end if;
					if w_ctr_cmpa = '1' then -- Counter equal to CMPA on up-count (CAU)
						case a_cau is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
						case b_cau is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
					end if;
					if w_ctr_cmpb = '1' then -- Counter equal to CMPB on up-count (CBU)
						case a_cbu is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
						case b_cbu is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
					end if;
					if w_ctr_prd = '1' then -- Counter equal to period (TBPRD)
					end if;
					
				when "01" => -- count down direction
					if w_ctr_prd = '1' then -- Counter equal to period (TBPRD)
						case a_prd is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
						case b_prd is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
					end if;
					if w_ctr_cmpa = '1' then -- Counter equal to CMPA on down-count (CAD)
						case a_cad is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
						case b_cad is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
					end if;
					if w_ctr_cmpb = '1' then -- Counter equal to CMPB on down-count (CBD)
						case a_cbd is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
						case b_cbd is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
					end if;
					if w_ctr_zero = '1' then -- Counter equals zero
						case a_zro is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
						case b_zro is
							when "00" =>
								-- do nothing
							when "01" =>
								w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
							when "10" =>
								w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
							when "11" =>
								w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
							when others => -- no options left, do nothing
						end case;
					end if;
					
				when "10" => -- count up-down direction
					case w_ctr_dir is
						when '0' => -- counting down
							-- commented cases are not supposed to happen during down counting
							--if w_ctr_cmpa = '1' then -- Counter equals CMPA on up-count (CAU)
							--end if;
							--if w_ctr_cmpb = '1' then -- Counter equals CMPB on up-count (CBU)
							--end if;
							if w_ctr_cmpa = '1' then -- Counter equal to CMPA on up-count (CAU)
								case a_cau is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
								case b_cau is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
							end if;
							if w_ctr_cmpa = '1' then -- Counter equals CMPA on down-count (CAD)
								case a_cad is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
								case b_cad is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
							end if;
							if w_ctr_cmpb = '1' then -- Counter equals CMPB on down-count (CBD)
								case a_cbd is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
								case b_cbd is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
							end if;
							
						when '1' => -- counting up
							-- commented cases are not supposed to happen during up counting
							--if w_ctr_cmpa = '1' then -- Counter equals CMPA on down-count (CAD)
							--end if;
							--if w_ctr_cmpb = '1' then -- Counter equals CMPB on down-count (CBD)
							--end if;
							if w_ctr_zero = '1' then -- Counter equals zero
								case a_zro is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
								case b_zro is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
							end if;
							if w_ctr_cmpa = '1' then -- Counter equals CMPA on up-count (CAU)
								case a_cau is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
								case b_cau is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
							end if;
							if w_ctr_cmpb = '1' then -- Counter equals CMPB on up-count (CBU)
								case a_cbu is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMA_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMA_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMA_aq <= not w_ePWMA_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
								case b_cbu is
									when "00" =>
										-- do nothing
									when "01" =>
										w_ePWMB_aq <= '0'; -- clear: force ePWMA output low
									when "10" =>
										w_ePWMB_aq <= '1'; -- Set: force ePWMA output high
									when "11" =>
										w_ePWMB_aq <= not w_ePWMB_aq; -- Toggle ePWMA output
									when others => -- no options left, do nothing
								end case;
							end if;
						when others => -- to avoid compiler error
					end case;
					
				when others => -- to avoid compiler error
			end case;
			-- Software forced event: TBD
	 
		end if;
	end process action_qualifier;
	
	dead_band : process(i_clk) is
	begin
		if rising_edge(i_clk) then
			-- S1 and S0 control (DBCTL[OUT_MODE])
			if db_out_mode(1)= '1' then
				w_ePWMA_db <= w_RED;
			else
				w_ePWMA_db <= w_ePWMA_aq;
			end if;
			if db_out_mode(0)= '1' then
				w_ePWMB_db <= w_FED;
			else
				w_ePWMB_db <= w_ePWMB_aq;
			end if;
			
			-- S3 and S2 control (DBCTL[POLSEL])
			if db_polsel(1)= '1' then
				w_FED <= not w_FED_ctr_out;
			else
				w_FED <= w_FED_ctr_out;
			end if;
			if db_polsel(0)= '1' then
				w_RED <= not w_RED_ctr_out;
			else
				w_RED <= w_RED_ctr_out;
			end if;
			
			-- S5 and S4 control (DBCTL[IN_MODE])
			if db_in_mode(1)= '1' then
				w_FED_ctr_in <= w_ePWMB_aq;
			else
				w_FED_ctr_in <= w_ePWMA_aq;
			end if;
			if db_in_mode(0)= '1' then
				w_RED_ctr_in <= w_ePWMB_aq ;
			else
				w_RED_ctr_in <= w_ePWMA_aq;
			end if;
			
			-- counter for full period here
			--RED
			if w_RED_ctr_in = '1' then
				if w_RED_ctr_out = '0' then
					w_RED_ctr <= w_RED_ctr + 1;
					if i_DBRED="0000000000" or w_RED_ctr >= i_DBRED-1 then
						w_RED_ctr_out <= '1';
					end if;
				end if;
			else
				w_RED_ctr_out <= '0';
				w_RED_ctr <= (others => '0');
			end if;
			--FED
			if w_FED_ctr_in = '0' then
				if w_FED_ctr_out = '1' then
					w_FED_ctr <= w_FED_ctr + 1;
					if i_DBFED="0000000000" or w_FED_ctr >= i_DBFED-1 then
						w_FED_ctr_out <= '0';
					end if;
				end if;
			else
				w_FED_ctr_out <= '1';
				w_FED_ctr <= (others => '0');
			end if;
		end if;
		
		if db_halfcycle = '1' then
			if i_clk = '0' then
				-- repeat counting for double period
				-- counter for full period here
				--RED
				if w_RED_ctr_in = '1' then
					if w_RED_ctr_out = '0' then
						w_RED_ctr <= w_RED_ctr + 1;
						if i_DBRED="0000000000" or w_RED_ctr >= i_DBRED-1 then
							w_RED_ctr_out <= '1';
						end if;
					end if;
				else
					w_RED_ctr_out <= '0';
					w_RED_ctr <= (others => '0');
				end if;
				--FED
				if w_FED_ctr_in = '0' then
					if w_FED_ctr_out = '1' then
						w_FED_ctr <= w_FED_ctr + 1;
						if i_DBFED="0000000000" or w_FED_ctr >= i_DBFED-1 then
							w_FED_ctr_out <= '0';
						end if;
					end if;
				else
					w_FED_ctr_out <= '1';
					w_FED_ctr <= (others => '0');
				end if;
			end if;
		end if;
	end process dead_band;
end rtl;
