DROP DATABASE IF EXISTS CasaDeVeio;
CREATE DATABASE CasaDeVeio;
USE CasaDeVeio;
CREATE TABLE Cuidador (
    id_cuidador INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(255) NOT NULL,
    cpf VARCHAR(14) NOT NULL UNIQUE,
    tel VARCHAR(20),
    data_nascimento DATE NOT NULL,
    endereco TEXT NOT NULL,
    salario DECIMAL(10, 2) NOT NULL,
    senha VARCHAR(255) NOT NULL -- Em um sistema real, isso armazenaria um hash da senha
);
CREATE TABLE Idoso (
    id_idoso INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(255) NOT NULL,
    cpf VARCHAR(14) NOT NULL UNIQUE,
    tel VARCHAR(20),
    data_nascimento DATE NOT NULL
);
CREATE TABLE Atividades (
    id_atividade INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL,
    descricao TEXT
);
CREATE TABLE Drogas (
    id_droga INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL UNIQUE,
    codigo_droga VARCHAR(50) UNIQUE
);
CREATE TABLE Problemas_Saude (
    id_problema INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL,
    tipo ENUM('Doenca','ALERGIA') NOT NULL,
    descricao_efeitos TEXT
);
CREATE TABLE LogLine (
    id_log INT PRIMARY KEY AUTO_INCREMENT,
    id_cuidador INT,
    data_hora DATETIME DEFAULT CURRENT_TIMESTAMP,
    log_line TEXT,
    FOREIGN KEY (id_cuidador) REFERENCES Cuidador(id_cuidador)
);
CREATE TABLE Log_Final (
    id_log_final INT PRIMARY KEY AUTO_INCREMENT,
    final_data TEXT,
    data_coleta DATE DEFAULT (CURRENT_DATE)
);
DROP TABLE IF EXISTS Cuidador_qual_Idoso;

CREATE TABLE Cuidador_qual_Idoso (
  id_idoso            INT          NOT NULL,
  id_cuidador         INT          NOT NULL,
  data_inicio_cuidado DATE         NOT NULL,
  data_fim_cuidado    DATE         NULL,
  id_droga_sugerida   INT          NULL,

  PRIMARY KEY (id_idoso),

  INDEX idx_cuidador       (id_cuidador),
  INDEX idx_droga_sugerida (id_droga_sugerida),

  FOREIGN KEY (id_idoso)
    REFERENCES Idoso (id_idoso),

  FOREIGN KEY (id_cuidador)
    REFERENCES Cuidador (id_cuidador),

  FOREIGN KEY (id_droga_sugerida)
    REFERENCES Drogas (id_droga)
) ENGINE=InnoDB
  DEFAULT CHARSET = utf8mb4;


  
CREATE TABLE Idoso_quais_Problemas (
    id_idoso_problema INT PRIMARY KEY AUTO_INCREMENT,
    id_idoso INT,
    id_problema INT,
    FOREIGN KEY (id_idoso) REFERENCES Idoso(id_idoso),
    FOREIGN KEY (id_problema) REFERENCES Problemas_Saude(id_problema)
);
  

CREATE TABLE Agenda_Idoso (
    id_agenda INT PRIMARY KEY AUTO_INCREMENT,
    id_idoso INT,
    id_atividade INT,
    quando_inicia DATETIME NOT NULL,
    quando_termina DATETIME NOT NULL,
    isDone BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (id_idoso) REFERENCES Idoso(id_idoso),
    FOREIGN KEY (id_atividade) REFERENCES Atividades(id_atividade)
);
CREATE VIEW Alerta_Idoso AS
SELECT
    cqi.id_cuidador AS id_funcionario,
    i.id_idoso,
    i.nome AS nome_idoso,
    ps.nome AS alergia,
    d.nome AS remedio_correspondente
FROM Idoso i
JOIN Idoso_quais_Problemas iqp ON i.id_idoso = iqp.id_idoso
JOIN Problemas_Saude ps ON iqp.id_problema = ps.id_problema
JOIN Drogas d ON ps.nome = d.nome
JOIN Cuidador_qual_Idoso cqi ON i.id_idoso = cqi.id_idoso
WHERE ps.tipo = 'Alergia';

CREATE VIEW Ativs_para_fazer AS
SELECT
    cqi.id_cuidador AS id_funcionario,
    c.nome AS nome_cuidador,
    ag.id_agenda,
    i.nome AS nome_idoso,
    a.nome AS nome_atividade,
    ag.quando_inicia,
    ag.quando_termina
FROM Agenda_Idoso ag
JOIN Atividades a ON ag.id_atividade = a.id_atividade
JOIN Idoso i ON ag.id_idoso = i.id_idoso
JOIN Cuidador_qual_Idoso cqi ON ag.id_idoso = cqi.id_idoso
JOIN Cuidador c ON cqi.id_cuidador = c.id_cuidador
WHERE ag.isDone = FALSE
  AND DATE(ag.quando_inicia) = CURRENT_DATE
ORDER BY ag.quando_inicia ASC;

CREATE VIEW Problemas_e_Solucoes AS
SELECT
    ps.nome AS problema_saude,
    ps.tipo,
    d.nome AS remedio_sugerido
FROM Problemas_Saude ps
JOIN Drogas d ON ps.nome LIKE CONCAT('%', d.nome, '%') OR d.nome LIKE CONCAT('%', ps.nome, '%')
WHERE
    ps.tipo = 'Doenca'
    AND d.nome NOT IN (SELECT nome FROM Problemas_Saude WHERE tipo = 'Alergia');
    
DELIMITER $$
CREATE TRIGGER Troca_Idoso
AFTER UPDATE ON Cuidador_qual_Idoso
FOR EACH ROW
BEGIN
  IF OLD.id_cuidador != NEW.id_cuidador THEN
    INSERT INTO LogLine (id_cuidador, log_line)
    VALUES (
      NEW.id_cuidador,
      CONCAT('Assumiu o cuidado do idoso #', NEW.id_idoso, ' a partir de hoje.')
    );

    INSERT INTO LogLine (id_cuidador, log_line)
    VALUES (
      OLD.id_cuidador,
      CONCAT('Deixou de cuidar do idoso #', OLD.id_idoso, '.')
    );
  END IF;
END$$

DELIMITER $$
CREATE TRIGGER Vincular_a_Cuidador
AFTER INSERT ON Idoso
FOR EACH ROW
BEGIN
  DECLARE cuidador_id INT;

  SELECT c.id_cuidador
    INTO cuidador_id
    FROM Cuidador c
    LEFT JOIN Cuidador_qual_Idoso cqi
      ON c.id_cuidador = cqi.id_cuidador
    GROUP BY c.id_cuidador
    ORDER BY COUNT(cqi.id_idoso) ASC
    LIMIT 1;

  IF cuidador_id IS NOT NULL THEN
    INSERT INTO Cuidador_qual_Idoso (
      id_cuidador,
      id_idoso,
      data_inicio_cuidado
    )
    VALUES (
      cuidador_id,
      NEW.id_idoso,
      CURRENT_DATE
    );
  END IF;
END$$

DELIMITER $$
CREATE TRIGGER nova_doenca
AFTER INSERT ON Problemas_Saude
FOR EACH ROW
BEGIN
  INSERT INTO LogLine (log_line)
  VALUES (
    CONCAT('Novo problema de saúde registrado: ', NEW.nome)
  );
END$$

DELIMITER $$
CREATE TRIGGER inserir_nos_logs
AFTER UPDATE ON Agenda_Idoso
FOR EACH ROW
BEGIN
    DECLARE cuidador_id INT;
    DECLARE nome_ativ  VARCHAR(100);
    DECLARE nome_idoso_str VARCHAR(255);

    IF NEW.isDone = TRUE AND OLD.isDone = FALSE THEN

        -- Pega apenas um cuidador (o mais recente, se houver vários)
        SELECT cqi.id_cuidador
          INTO cuidador_id
          FROM Cuidador_qual_Idoso cqi
         WHERE cqi.id_idoso = NEW.id_idoso
         ORDER BY cqi.data_inicio_cuidado DESC
         LIMIT 1;

        SELECT a.nome 
          INTO nome_ativ 
          FROM Atividades a 
         WHERE a.id_atividade = NEW.id_atividade;

        SELECT i.nome 
          INTO nome_idoso_str 
          FROM Idoso i 
         WHERE i.id_idoso = NEW.id_idoso;

        IF cuidador_id IS NOT NULL THEN
            INSERT INTO LogLine (id_cuidador, log_line)
            VALUES (
              cuidador_id,
              CONCAT('Concluiu a atividade "', nome_ativ,
                     '" para o idoso(a) ', nome_idoso_str, '.')
            );
        END IF;

    END IF;
END$$

DELIMITER $$
CREATE TRIGGER verifica_horarios_compativeis
BEFORE INSERT ON Agenda_Idoso
FOR EACH ROW
BEGIN
  DECLARE cid INT;

  IF EXISTS (
    SELECT 1
    FROM Agenda_Idoso
    WHERE id_idoso       = NEW.id_idoso
      AND NEW.quando_inicia < quando_termina
      AND NEW.quando_termina > quando_inicia
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Conflito de horário: idoso já possui atividade neste período.';
  END IF;

  SELECT id_cuidador
    INTO cid
    FROM Cuidador_qual_Idoso
    WHERE id_idoso = NEW.id_idoso
    LIMIT 1;

  IF cid IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM Agenda_Idoso ag
      JOIN Cuidador_qual_Idoso cqi
        ON ag.id_idoso = cqi.id_idoso
      WHERE cqi.id_cuidador  = cid
        AND NEW.quando_inicia < ag.quando_termina
        AND NEW.quando_termina > ag.quando_inicia
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Conflito de horário: cuidador já está ocupado neste período.';
  END IF;
END$$


DELIMITER ;

DELIMITER $$
CREATE EVENT IF NOT EXISTS reiniciar_ativs
ON SCHEDULE
  EVERY 1 DAY
  STARTS CONCAT(CURRENT_DATE, ' 00:00:00')
DO
BEGIN
  UPDATE Agenda_Idoso
    SET isDone = FALSE
    WHERE DATE(quando_inicia) < CURRENT_DATE
      AND isDone = TRUE;
END$$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE Vincular_Problema_Idoso(IN idoso_id INT, IN problema_id INT)
BEGIN
    START TRANSACTION;
    INSERT INTO Idoso_quais_Problemas (id_idoso, id_problema)
    VALUES (idoso_id, problema_id);
    COMMIT;
END$$

DELIMITER $$
CREATE PROCEDURE coletar_logs()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE cuidador_id INT;
    DECLARE cuidador_nome VARCHAR(255);
    DECLARE total_atividades INT;
    DECLARE atividades_feitas INT;
    DECLARE porcentagem FLOAT;
    DECLARE log_final_texto TEXT;
    DECLARE logs_do_cuidador TEXT;

    DECLARE cur_cuidador CURSOR FOR SELECT id_cuidador, nome FROM Cuidador;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;


    START TRANSACTION;

    OPEN cur_cuidador;

    loop_cuidador: LOOP
        FETCH cur_cuidador INTO cuidador_id, cuidador_nome;
        IF done THEN
            LEAVE loop_cuidador;
        END IF;

        SELECT COUNT(*) INTO total_atividades
        FROM Agenda_Idoso ag
        JOIN Cuidador_qual_Idoso cqi ON ag.id_idoso = cqi.id_idoso
        WHERE cqi.id_cuidador = cuidador_id AND DATE(ag.quando_inicia) = CURRENT_DATE;

        SELECT COUNT(*) INTO atividades_feitas
        FROM Agenda_Idoso ag
        JOIN Cuidador_qual_Idoso cqi ON ag.id_idoso = cqi.id_idoso
        WHERE cqi.id_cuidador = cuidador_id AND DATE(ag.quando_inicia) = CURRENT_DATE AND ag.isDone = TRUE;

        IF total_atividades > 0 THEN
            SET porcentagem = (atividades_feitas / total_atividades) * 100;
        ELSE
            SET porcentagem = 0;
        END IF;

        SELECT GROUP_CONCAT(log_line SEPARATOR '; ') INTO logs_do_cuidador
        FROM LogLine
        WHERE id_cuidador = cuidador_id AND DATE(data_hora) = CURRENT_DATE;

        SET log_final_texto = CONCAT(
            'Relatório do Cuidador: ', cuidador_nome, ' (ID: ', cuidador_id, ') - Data: ', CURRENT_DATE, '\n',
            'Performance: ', FORMAT(porcentagem, 2), '% das atividades concluídas (', atividades_feitas, ' de ', total_atividades, ').\n',
            'Logs do dia: ', IFNULL(logs_do_cuidador, 'Nenhuma atividade registrada.')
        );

        INSERT INTO Log_Final (final_data) VALUES (log_final_texto);

    END LOOP;

    CLOSE cur_cuidador;

    TRUNCATE TABLE LogLine;

    COMMIT;
END$$
DELIMITER ;


INSERT INTO Cuidador (nome, cpf, tel, data_nascimento, endereco, salario, senha) VALUES
('João Silva', '123.456.789-00', '123456789', '1980-01-01', 'Rua A, 123', 3000.00, 'senha123'),
('Maria Oliveira', '987.654.321-00', '987654321', '1975-05-05', 'Rua B, 456', 3200.00, 'senha456'),
('Carlos Pereira', '456.789.123-00', '456789123', '1982-02-02', 'Rua C, 789', 3100.00, 'senha789');

INSERT INTO Idoso (nome, cpf, tel, data_nascimento) VALUES
('Antônio Souza', '111.222.333-44', '111222333', '1940-03-03'), 
('Fulano Teste', '000.000.000-00', '000000000', '1930-01-01'),   
('Nilton Santos', '222.333.444-55', '222333444', '1938-04-04'), 
('Mariana Lima', '333.444.555-66', '333444555', '1935-05-05');  

SELECT 
    c.nome AS cuidador, 
    i.nome AS idoso, 
    cqi.data_inicio_cuidado
FROM Cuidador c
JOIN Cuidador_qual_Idoso cqi ON c.id_cuidador = cqi.id_cuidador
JOIN Idoso i ON cqi.id_idoso = i.id_idoso;


INSERT INTO Drogas (nome, codigo_droga) VALUES
('Paracetamol', 'PARA123'),   
('Dipirona', 'DIPI456'),      
('Omeprazol', 'OMEP789');     

INSERT INTO Problemas_Saude (nome, tipo, descricao_efeitos) VALUES
('Dipirona', 'ALERGIA', 'Reações alérgicas graves');

CALL Vincular_Problema_Idoso(1,1); 

TRUNCATE TABLE Cuidador_qual_Idoso;
INSERT INTO Cuidador_qual_Idoso (id_cuidador, id_idoso, data_inicio_cuidado, id_droga_sugerida) VALUES
(1, 3, CURRENT_DATE, 1), 
(2, 1, CURRENT_DATE, 2), 
(3, 4, CURRENT_DATE, 3); 


SELECT 
    c.id_cuidador, 
    c.nome AS cuidador, 
    i.id_idoso, 
    i.nome AS idoso, 
    d.nome AS remedio_sugerido, 
    CASE 
        WHEN ps.tipo = 'ALERGIA' THEN 'CONFLITO'
        ELSE 'OK'
    END AS status
FROM Cuidador c
JOIN Cuidador_qual_Idoso cqi ON c.id_cuidador = cqi.id_cuidador
JOIN Idoso i ON cqi.id_idoso = i.id_idoso
JOIN Drogas d ON cqi.id_droga_sugerida = d.id_droga
LEFT JOIN Idoso_quais_Problemas iqp ON i.id_idoso = iqp.id_idoso
LEFT JOIN Problemas_Saude ps ON iqp.id_problema = ps.id_problema AND ps.nome = d.nome;



