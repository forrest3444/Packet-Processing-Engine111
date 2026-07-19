interface ppe_fe_if;
	logic         in_valid;
	logic [127:0] in_data;
	logic         dep_valid;
	logic [127:0] dep_data;
	logic [1:0]   lat;

	logic         out_valid;
	logic [127:0] out_data;

endinterface
