//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           ov5640_dri
// Last modified Date:  2020/05/04 9:19:08
// Last Version:        V1.0
// Descriptions:        OV5640����ͷ����
//                      
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2019/05/04 9:19:08
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module ov5640_dri (
    input           clk             ,  //ʱ��
    input           rst_n           ,  //��λ�ź�,�͵�ƽ��Ч
    //����ͷ�ӿ� 
    input           cam_pclk        ,  //cmos ��������ʱ��
    input           cam_vsync       ,  //cmos ��ͬ���ź�
    input           cam_href        ,  //cmos ��ͬ���ź�
    input    [7:0]  cam_data        ,  //cmos ����  
    output          cam_rst_n       ,  //cmos ��λ�źţ��͵�ƽ��Ч
    output          cam_pwdn        ,  //cmos ��Դ����ģʽѡ���ź�
    output          cam_scl         ,  //cmos SCCB_SCL��
    inout           cam_sda         ,  //cmos SCCB_SDA��
    
    //����ͷ�ֱ������ýӿ�
    input    [12:0] cmos_h_pixel    ,  //ˮƽ����ֱ���
    input    [12:0] cmos_v_pixel    ,  //��ֱ����ֱ���
    input    [12:0] total_h_pixel   ,  //ˮƽ�����ش�С
    input    [12:0] total_v_pixel   ,  //��ֱ�����ش�С
    input           capture_start   ,  //ͼ��ɼ���ʼ�ź�
    output          cam_init_done   ,  //����ͷ��ʼ�����
    
    //�û��ӿ�
    output          cmos_frame_vsync,  //֡��Ч�ź�    
    output          cmos_frame_href ,  //����Ч�ź�
    output          cmos_frame_valid,  //������Чʹ���ź�
    output  [15:0]  cmos_frame_data    //��Ч����  
);

//parameter define
parameter SLAVE_ADDR = 7'h3c          ; //OV5640��������ַ7'h3c
parameter BIT_CTRL   = 1'b1           ; //OV5640���ֽڵ�ַΪ16λ  0:8λ 1:16λ
parameter CLK_FREQ   = 27'd50_000_000 ; //i2c_driģ�������ʱ��Ƶ�� 
parameter I2C_FREQ   = 18'd250_000    ; //I2C��SCLʱ��Ƶ��,������400KHz

//wire difine
wire        i2c_exec       ;  //I2C����ִ���ź�
wire [23:0] i2c_data       ;  //I2CҪ���õĵ�ַ������(��8λ��ַ,��8λ����)          
wire        i2c_done       ;  //I2C�Ĵ�����������ź�
wire        i2c_dri_clk    ;  //I2C����ʱ��
wire [ 7:0] i2c_data_r     ;  //I2C����������
wire        i2c_rh_wl      ;  //I2C��д�����ź�

//*****************************************************
//**                    main code                      
//*****************************************************

//��Դ����ģʽѡ�� 0������ģʽ 1����Դ����ģʽ
assign  cam_pwdn  = 1'b0;
assign  cam_rst_n = 1'b1;
    
//I2C����ģ��
i2c_ov5640_rgb565_cfg u_i2c_cfg(
    .clk                (i2c_dri_clk),
    .rst_n              (rst_n),
            
    .i2c_exec           (i2c_exec),
    .i2c_data           (i2c_data),
    .i2c_rh_wl          (i2c_rh_wl),        //I2C��д�����ź�
    .i2c_done           (i2c_done), 
    .i2c_data_r         (i2c_data_r),   
                
    .cmos_h_pixel       (cmos_h_pixel),     //CMOSˮƽ�������ظ���
    .cmos_v_pixel       (cmos_v_pixel) ,    //CMOS��ֱ�������ظ���
    .total_h_pixel      (total_h_pixel),    //ˮƽ�����ش�С
    .total_v_pixel      (total_v_pixel),    //��ֱ�����ش�С
        
    .init_done          (cam_init_done) 
    );    

//I2C����ģ��
i2c_dri #(
    .SLAVE_ADDR         (SLAVE_ADDR),       //��������
    .CLK_FREQ           (CLK_FREQ  ),              
    .I2C_FREQ           (I2C_FREQ  ) 
    )
u_i2c_dr(
    .clk                (clk),
    .rst_n              (rst_n     ),

    .i2c_exec           (i2c_exec  ),   
    .bit_ctrl           (BIT_CTRL  ),   
    .i2c_rh_wl          (i2c_rh_wl),        //�̶�Ϊ0��ֻ�õ���IIC������д����   
    .i2c_addr           (i2c_data[23:8]),   
    .i2c_data_w         (i2c_data[7:0]),   
    .i2c_data_r         (i2c_data_r),   
    .i2c_done           (i2c_done  ),
    
    .scl                (cam_scl   ),   
    .sda                (cam_sda   ),   

    .dri_clk            (i2c_dri_clk)       //I2C����ʱ��
    );

//CMOSͼ�����ݲɼ�ģ��
cmos_capture_data u_cmos_capture_data(
    .rst_n              (rst_n),  // 只使用系统复位

    .cam_pclk           (cam_pclk),
    .cam_vsync          (cam_vsync),
    .cam_href           (cam_href),  // 直接使用cam_href，不受capture_start控制（调试模式）
    .cam_data           (cam_data),

    .cmos_frame_vsync   (cmos_frame_vsync),
    .cmos_frame_href    (cmos_frame_href ),
    .cmos_frame_valid   (cmos_frame_valid), //������Чʹ���ź�
    .cmos_frame_data    (cmos_frame_data )  //��Ч����
    );

endmodule 